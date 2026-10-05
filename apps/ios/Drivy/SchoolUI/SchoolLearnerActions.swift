import SwiftUI

/// Coordonnées qu’une école a enregistrées pour joindre un élève.
struct SchoolLearnerContact: Equatable {
    var email: String?
    var phone: String?
}

/// Un geste de contact : appeler, écrire un message, écrire un e-mail.
/// Il n’existe que pour une coordonnée enregistrée et exploitable, jamais devinée.
struct SchoolLearnerContactLink: Identifiable, Equatable {
    enum Kind: String { case call = "phone", message, mail = "email" }

    let kind: Kind
    let url: URL
    /// Coordonnée utilisée : VoiceOver la lit, l’écran ne l’affiche pas.
    let value: String

    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .call: "Appeler"
        case .message: "Envoyer un message"
        case .mail: "Envoyer un e-mail"
        }
    }

    var symbol: String {
        switch kind {
        case .call: "phone"
        case .message: "message"
        case .mail: "envelope"
        }
    }

    static func links(for contact: SchoolLearnerContact) -> [SchoolLearnerContactLink] {
        var links: [SchoolLearnerContactLink] = []
        if let phone = contact.phone {
            if let url = SchoolContactLinks.call(phone) {
                links.append(SchoolLearnerContactLink(kind: .call, url: url, value: phone))
            }
            if let url = SchoolContactLinks.message(phone) {
                links.append(SchoolLearnerContactLink(kind: .message, url: url, value: phone))
            }
        }
        if let email = contact.email, let url = SchoolContactLinks.mail(email) {
            links.append(SchoolLearnerContactLink(kind: .mail, url: url, value: email))
        }
        return links
    }
}

/// Les gestes fréquents envers un élève, sans afficher ses coordonnées en toutes lettres.
/// Pastilles de 44 pt côte à côte ; aux tailles d’accessibilité, des lignes libellées empilées.
/// Sans coordonnée exploitable ni profil à ouvrir, la vue ne prend aucune place.
struct SchoolLearnerActions: View {
    let learner: SchoolLearner
    var openProfile: (() -> Void)? = nil
    /// Coordonnées relues ailleurs (profil administratif) ; par défaut celles du dossier.
    var contact: SchoolLearnerContact? = nil
    /// Préfixe des identifiants de test : « préfixe-phone », « préfixe-message », « préfixe-email ».
    var identifierPrefix: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast

    private var links: [SchoolLearnerContactLink] {
        SchoolLearnerContactLink.links(for: contact
            ?? SchoolLearnerContact(email: learner.contactEmail, phone: learner.contactPhone))
    }

    var body: some View {
        let contactLinks = links
        if openProfile != nil || !contactLinks.isEmpty {
            let stacked = typeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
                : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
            layout {
                if let openProfile {
                    profileButton(openProfile)
                    if !stacked { Spacer(minLength: 0) }
                }
                ForEach(contactLinks) { link in contactButton(link, stacked: stacked) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }

    private func profileButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: DrivySpacing.xs) {
                Label("Profil", systemImage: "person.text.rectangle")
                if learner.profileReadiness == "ACTION_REQUIRED" {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(DrivyTheme.warning).accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DrivyTheme.accent)
        .accessibilityLabel(learner.profileReadiness == "ACTION_REQUIRED" ? "Profil à vérifier" : "Profil")
        .accessibilityIdentifier("open-learner-profile")
    }

    private func contactButton(_ link: SchoolLearnerContactLink, stacked: Bool) -> some View {
        Link(destination: link.url) {
            if stacked {
                Label(link.title, systemImage: link.symbol)
                    .font(.body.weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            } else {
                Image(systemName: link.symbol)
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .overlay {
                        // Même renfort que le bouton secondaire : le remplissage seul se détache mal d’une page blanche.
                        if contrast == .increased { Circle().strokeBorder(DrivyTheme.accent, lineWidth: 1) }
                    }
                    .contentShape(Circle())
            }
        }
        .foregroundStyle(DrivyTheme.accent)
        .accessibilityLabel(link.title)
        .accessibilityValue(link.value)
        .accessibilityIdentifier(identifierPrefix.map { "\($0)-\(link.kind.rawValue)" } ?? "")
    }
}
