import SwiftUI

/// Prénom et nom enregistrés au profil, comparés au nom déjà affiché en tête d’écran.
/// Hors de la vue : la règle se teste telle quelle.
enum SchoolLearnerRecordedName {
    /// Dans l’ordre de lecture ; vide si ni le prénom ni le nom ne sont renseignés.
    static func text(firstName: String?, lastName: String?) -> String {
        [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Vrai quand le nom du profil redit celui déjà affiché, à la casse et aux espaces près.
    static func repeats(_ recordedName: String, displayedName: String?) -> Bool {
        guard let displayedName else { return false }
        return folded(recordedName).compare(folded(displayedName), options: .caseInsensitive) == .orderedSame
    }

    private static func folded(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Read-only personal details of the learner's profile, in clear: contacts, then birth date and
/// address when the rights give them. Its owner loads the workspace and presents loading, errors
/// and editing; this view never reads the editable draft.
struct SchoolLearnerProfileSummary: View {
    let model: SchoolProfileWorkspace
    /// Name already shown at the top of the screen: the profile's first and last name are then
    /// repeated only when they differ from it.
    var displayedName: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let profile = model.profile {
            let recordedName = SchoolLearnerRecordedName.text(firstName: profile.firstName, lastName: profile.lastName)
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                if !SchoolLearnerRecordedName.repeats(recordedName, displayedName: displayedName) {
                    valueRow("Prénom et nom", value: recordedName, identifier: "learner-profile-name")
                }
                valueRow("E-mail", value: profile.contactEmail, identifier: "learner-profile-email-value")
                valueRow("Téléphone", value: profile.contactPhone, identifier: "learner-profile-phone-value")
                // CONTACT projections omit these fields; omission must never read as missing data.
                if model.isOwnProfile || model.roles.contains("ADMIN") {
                    valueRow("Date de naissance", value: SchoolProfileDraft.displayDate(profile.birthDate),
                             missing: "Non renseignée", identifier: "learner-profile-birth-date")
                    valueRow("Adresse", value: profile.postalAddress.map(addressText),
                             missing: "Non renseignée", identifier: "learner-profile-address")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func valueRow(_ title: String, value: String?, missing: String = "Non renseigné",
                          identifier: String) -> some View {
        let content = nonempty(value)
        return row(title, value: content ?? missing, tone: content == nil ? DrivyTheme.muted : DrivyTheme.text)
            .textSelection(.enabled)
            .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func row(_ title: String, value: String, tone: Color) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    Text(value).font(.body).foregroundStyle(tone)
                }
            } else {
                LabeledContent {
                    Text(value)
                        .foregroundStyle(tone)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                } label: {
                    Text(title).foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.body)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func addressText(_ address: SchoolPostalAddress) -> String {
        let country = Locale.current.localizedString(forRegionCode: address.countryCode) ?? address.countryCode
        return [address.line1, nonempty(address.line2), "\(address.postalCode) \(address.locality)", country]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
