import Foundation
import Observation

/// Dernier choix de photo pas encore confirmé par l’école (#118).
enum SchoolSelfPhotoIntent: Equatable {
    case replace(Data)
    case remove

    var jpeg: Data? { if case .replace(let data) = self { data } else { nil } }
}

/// La saisie du compte Drivy de la personne connectée (`/v1/me/profile`) : nom affiché, prénom, nom, contact,
/// naissance et adresse. Cette source appartient à la personne, quel que soit son rôle ou son école ; elle ne touche
/// jamais un dossier scolaire. La photo suit son propre envoi, tenu par `SchoolWorkspace`.
///
/// #118 : la photo choisie s’affiche ici dès son cadrage, marquée « en cours » ; les autres ne la voient qu’après
/// l’accord de l’école. Compte et photo partagent la version de la personne : leurs envois partent l’un après
/// l’autre, jamais en parallèle, et seul le dernier choix de photo part.
@MainActor @Observable
final class SchoolSelfProfileEditor {
    var edit = SchoolSelfProfileEdit(displayName: "", firstName: "", lastName: "", contactPhone: "")
    var hasAddress = false
    var address = SchoolSelfProfileEditor.emptyAddress
    private(set) var loaded: SchoolSelfProfileEdit?
    private(set) var isLoading = true
    private(set) var isSaving = false
    private(set) var isSavingPhoto = false
    /// Dernier échec de lecture ou d’enregistrement du compte, dit tel quel ; la saisie reste en place.
    private(set) var errorMessage: String?
    /// La photo s’enregistre seule, dès qu’elle est cadrée (#155) : son échec et son résultat se lisent près d’elle.
    private(set) var photoErrorMessage: String?
    private(set) var photoResult: String?
    /// Une photo a été enregistrée ou retirée pendant cette ouverture : fermer sans enregistrer ne l’annule pas.
    private(set) var photoChanged = false
    /// Choix de photo affiché ici avant la réponse de l’école ; `nil` : la photo enregistrée.
    private(set) var photoIntent: SchoolSelfPhotoIntent?
    /// Choix refusé ou non confirmé, à renvoyer tel quel.
    private(set) var failedPhoto: SchoolSelfPhotoIntent?
    @ObservationIgnored private let workspace: SchoolWorkspace
    /// File des envois du compte : un envoi attend la fin du précédent (même version de personne).
    @ObservationIgnored private var chain: Task<Void, Never>?

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
        // Dans la file : une photo choisie juste avant ou juste après part avant ou après, jamais en même temps.
        let previous = chain
        let work = Task { @MainActor [weak self] () -> Bool in
            await previous?.value
            return await self?.send(value) ?? false
        }
        chain = Task { @MainActor in _ = await work.value }
        return await work.value
    }

    private func send(_ value: SchoolSelfProfileEdit) async -> Bool {
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

    /// Photo affichée dans l’éditeur : le dernier choix en cours, sinon la photo enregistrée.
    func displayedPhoto(confirmed: Data?) -> Data? {
        guard let photoIntent else { return confirmed }
        return photoIntent.jpeg
    }
    /// Une photo est affichée (enregistrée ou en cours) : elle peut être retirée.
    func showsPhoto(confirmedVersion: Int?) -> Bool {
        photoIntent.map { $0 != .remove } ?? (confirmedVersion != nil)
    }

    /// Remplace (`jpeg`) ou retire (`nil`) la photo. Retour immédiat dans l’éditeur ; un choix plus récent remplace
    /// celui qui n’est pas encore parti, et l’envoi attend celui du compte.
    func choosePhoto(_ jpeg: Data?) {
        let intent: SchoolSelfPhotoIntent = jpeg.map { .replace($0) } ?? .remove
        photoIntent = intent; failedPhoto = nil; photoErrorMessage = nil; photoResult = nil
        enqueue { [weak self] in await self?.sendPhoto(intent) }
    }

    func retryPhoto() {
        guard let failedPhoto else { return }
        choosePhoto(failedPhoto.jpeg)
    }

    private func sendPhoto(_ intent: SchoolSelfPhotoIntent) async {
        // Dépassé par un choix plus récent : seul le dernier part.
        guard photoIntent == intent else { return }
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        do {
            try await workspace.setSelfPhoto(intent.jpeg)
            photoChanged = true
            if photoIntent == intent {
                photoIntent = nil
                photoResult = intent == .remove ? "Photo retirée." : "Photo enregistrée."
            }
        } catch {
            // L’éditeur revient à la photo enregistrée ; le choix reste disponible pour « Réessayer ».
            if photoIntent == intent {
                photoIntent = nil
                failedPhoto = intent
                photoErrorMessage = Self.message(error)
            }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }

    func failPhoto() { photoResult = nil; photoErrorMessage = SchoolSelfProfileFailure.invalidPhoto.localizedDescription }

    private static func message(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
    }
}
