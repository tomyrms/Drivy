import SwiftUI

/// Read-only contents of the learner's profile panel. Its owner loads the workspace
/// and presents loading, errors and editing; this view never reads the editable draft.
struct SchoolLearnerProfileSummary: View {
    let model: SchoolProfileWorkspace
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let profile = model.profile {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                VStack(alignment: .leading, spacing: DrivySpacing.s) {
                    valueRow("Prénom", value: profile.firstName, identifier: "learner-profile-first-name")
                    valueRow("Nom", value: profile.lastName, identifier: "learner-profile-last-name")
                }
                Divider()
                VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                    contactRow("E-mail", value: profile.contactEmail, scheme: "mailto",
                               action: "Envoyer un e-mail", identifier: "learner-profile-email")
                    contactRow("Téléphone", value: profile.contactPhone, scheme: "tel",
                               action: "Appeler", identifier: "learner-profile-phone")
                }
                // CONTACT projections omit these fields; omission must never read as missing data.
                if model.isOwnProfile || model.roles.contains("ADMIN") {
                    Divider()
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        valueRow("Date de naissance", value: SchoolProfileDraft.displayDate(profile.birthDate),
                                 missing: "Non renseignée", identifier: "learner-profile-birth-date")
                        valueRow("Adresse", value: profile.postalAddress.map(addressText),
                                 missing: "Non renseignée", identifier: "learner-profile-address")
                    }
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

    @ViewBuilder private func contactRow(_ title: String, value: String?, scheme: String,
                                        action: String, identifier: String) -> some View {
        if let value = nonempty(value), let destination = contactURL(scheme: scheme, value: value) {
            Link(destination: destination) {
                row(title, value: value, tone: DrivyTheme.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action)
            .accessibilityValue(value)
            .accessibilityIdentifier(identifier)
        } else {
            valueRow(title, value: value, identifier: identifier)
                .frame(minHeight: 44, alignment: .leading)
        }
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

    private func contactURL(scheme: String, value: String) -> URL? {
        scheme == "tel" ? SchoolContactLinks.call(value) : SchoolContactLinks.mail(value)
    }

    private func addressText(_ address: SchoolPostalAddress) -> String {
        let country = Locale.current.localizedString(forRegionCode: address.countryCode) ?? address.countryCode
        return [address.line1, nonempty(address.line2), "\(address.postalCode) \(address.locality)", country]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
