import SwiftUI

/// Les actions de la personne restent visibles avant les leçons et la progression.
struct SchoolLearnerActions: View {
    let learner: SchoolLearner
    var openProfile: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DrivySpacing.xs))
            : AnyLayout(HStackLayout(spacing: DrivySpacing.s))
        layout {
            if let openProfile {
                Button(action: openProfile) {
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
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            HStack(spacing: DrivySpacing.xs) {
                if let phone = learner.contactPhone {
                    if let url = SchoolContactLinks.call(phone) { contact("Appeler", symbol: "phone", url: url) }
                    if let url = SchoolContactLinks.message(phone) { contact("Envoyer un message", symbol: "message", url: url) }
                }
                if let email = learner.contactEmail, let url = SchoolContactLinks.mail(email) {
                    contact("Envoyer un e-mail", symbol: "envelope", url: url)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func contact(_ title: String, symbol: String, url: URL) -> some View {
        Link(destination: url) {
            Image(systemName: symbol).font(.body.weight(.medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .foregroundStyle(DrivyTheme.accent)
        .accessibilityLabel("\(title) · \(learner.displayName)")
    }
}
