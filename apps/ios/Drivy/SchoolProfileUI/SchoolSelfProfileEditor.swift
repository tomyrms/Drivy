import Foundation
import Observation

/// La saisie du compte Drivy de la personne connectée (`/v1/me/profile`) : nom affiché, prénom, nom, contact,
/// naissance et adresse. Cette source appartient à la personne, quel que soit son rôle ou son école ; elle ne touche
/// jamais un dossier scolaire. La photo suit son propre envoi, tenu par `SchoolWorkspace`.
@MainActor @Observable
final class SchoolSelfProfileEditor {
    var edit = SchoolSelfProfileEdit(displayName: "", firstName: "", lastName: "", contactPhone: "")
    var hasAddress = false
    var address = SchoolSelfProfileEditor.emptyAddress
    private(set) var loaded: SchoolSelfProfileEdit?
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var isSavingPhoto = false
    /// Dernier échec de lecture, d’enregistrement ou de photo du compte, dit tel quel ; la saisie reste en place.
    private(set) var errorMessage: String?
    @ObservationIgnored private let workspace: SchoolWorkspace

    nonisolated static let emptyAddress = SchoolPostalAddress(line1: "", line2: nil, postalCode: "", locality: "", countryCode: "")

    init(workspace: SchoolWorkspace) { self.workspace = workspace }

    private func clean(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanAddress: SchoolPostalAddress? {
        guard hasAddress else { return nil }
        let line2 = clean(address.line2 ?? "")
        return SchoolPostalAddress(line1: clean(address.line1), line2: line2.isEmpty ? nil : line2, postalCode: clean(address.postalCode),
            locality: clean(address.locality), countryCode: address.countryCode)
    }
    /// Ce qui partirait : les valeurs saisies, sans espaces de bord.
    var trimmed: SchoolSelfProfileEdit {
        SchoolSelfProfileEdit(displayName: clean(edit.displayName), firstName: clean(edit.firstName),
            lastName: clean(edit.lastName), contactPhone: clean(edit.contactPhone), contactEmail: clean(edit.contactEmail),
            birthDate: edit.birthDate, postalAddress: cleanAddress)
    }
    var phoneValid: Bool {
        let phone = trimmed.contactPhone
        return phone.isEmpty || (phone.count >= 3 && phone.count <= 32 && phone.allSatisfy { "+0123456789 ().-/".contains($0) })
    }
    var emailValid: Bool {
        let email = trimmed.contactEmail
        return email.isEmpty || (email.count <= 254 && email.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil)
    }
    var addressValid: Bool { cleanAddress?.isValid ?? true }
    var displayNameValid: Bool { !trimmed.displayName.isEmpty && trimmed.displayName.count <= 200 }
    var valid: Bool {
        displayNameValid && trimmed.firstName.count <= 150 && trimmed.lastName.count <= 150 && phoneValid && emailValid && addressValid
    }
    /// Le profil n’a pas été lu : rien n’est comparé à une valeur inconnue, rien n’est enregistré.
    var hasEdits: Bool { loaded.map { trimmed != $0 } ?? false }
    var canSave: Bool { hasEdits && valid && !isSaving && !isSavingPhoto && !isLoading }
    var isBusy: Bool { isSaving || isSavingPhoto }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            fill(from: try await workspace.loadSelfProfile())
            errorMessage = nil
        } catch {
            // Le nom du compte reste modifiable même si le profil complet ne se lit pas.
            if loaded == nil, let person = workspace.person {
                fill(from: SchoolSelfProfile(personId: person.personId, displayName: person.displayName, version: person.version))
            }
            errorMessage = Self.message(error)
        }
    }

    private func fill(from profile: SchoolSelfProfile) {
        let value = SchoolSelfProfileEdit(profile)
        edit = value; loaded = value
        hasAddress = profile.postalAddress != nil
        address = profile.postalAddress ?? Self.emptyAddress
    }

    /// `true` seulement après la réponse de l’école ; un échec garde la saisie. Un conflit relit la version
    /// enregistrée comme référence, sans écraser ce qui est saisi : la personne vérifie puis renvoie.
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true; errorMessage = nil
        defer { isSaving = false }
        let value = trimmed
        do {
            try await workspace.saveSelfProfile(value)
            loaded = value
            if let profile = workspace.selfProfile { loaded = SchoolSelfProfileEdit(profile); if trimmed == value { fill(from: profile) } }
            return true
        } catch {
            if case SchoolSelfProfileFailure.changed = error, let profile = workspace.selfProfile { loaded = SchoolSelfProfileEdit(profile) }
            errorMessage = Self.message(error)
            return false
        }
    }

    /// Remplace (`jpeg`) ou retire (`nil`) la photo ; elle n’apparaît qu’après l’accord de l’école.
    func setPhoto(_ jpeg: Data?) async -> Bool {
        guard !isSavingPhoto else { return false }
        isSavingPhoto = true; errorMessage = nil
        defer { isSavingPhoto = false }
        do { try await workspace.setSelfPhoto(jpeg); return true }
        catch { errorMessage = Self.message(error); return false }
    }

    func failPhoto() { errorMessage = SchoolSelfProfileFailure.invalidPhoto.localizedDescription }

    private static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
    }
}
