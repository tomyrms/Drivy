import SwiftUI

/// Champs des écrans de compte (connexion, code, création, ouverture d’école).
enum SchoolAccountFieldID: Hashable {
    case email, password, code, firstName, lastName, displayName, schoolName, contactEmail, phone
}

/// Nature d’un champ : clavier, remplissage automatique et saisie masquée.
enum SchoolAccountFieldKind {
    case email, currentPassword, newPassword, givenName, familyName, name, organization, phone

    var contentType: UITextContentType {
        switch self {
        case .email: .username
        case .currentPassword: .password
        case .newPassword: .newPassword
        case .givenName: .givenName
        case .familyName: .familyName
        case .name: .name
        case .organization: .organizationName
        case .phone: .telephoneNumber
        }
    }
    var keyboard: UIKeyboardType {
        switch self {
        case .email: .emailAddress
        case .phone: .phonePad
        default: .default
        }
    }
    var isSecure: Bool { self == .currentPassword || self == .newPassword }
    var capitalization: TextInputAutocapitalization {
        switch self {
        case .email, .currentPassword, .newPassword: .never
        default: .words
        }
    }
}

/// Libellé permanent, champ dans le cadre des écrans « Rejoindre », puis l’erreur sous le champ.
struct SchoolAccountField: View {
    let label: String
    @Binding var text: String
    let kind: SchoolAccountFieldKind
    let id: SchoolAccountFieldID
    var focus: FocusState<SchoolAccountFieldID?>.Binding
    var error: String? = nil
    var hint: String? = nil
    var identifier: String
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}
    @State private var reveals = false

    var body: some View {
        SchoolJoinFieldBlock(label: label, error: error) {
            HStack(spacing: DrivySpacing.s) {
                input
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .textContentType(kind.contentType)
                    .keyboardType(kind.keyboard)
                    .textInputAutocapitalization(kind.capitalization)
                    .autocorrectionDisabled()
                    .submitLabel(submitLabel)
                    .onSubmit(onSubmit)
                    .focused(focus, equals: id)
                    .accessibilityLabel(label)
                    .accessibilityHint(error ?? hint ?? "")
                    .accessibilityIdentifier(identifier)
                if kind.isSecure {
                    Button { reveals.toggle() } label: {
                        Image(systemName: reveals ? "eye.slash" : "eye")
                            .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityLabel(reveals ? "Masquer le mot de passe" : "Afficher le mot de passe")
                }
            }
            .schoolJoinFieldChrome(hasError: error != nil, isFocused: focus.wrappedValue == id, minHeight: 52)
            if let hint, error == nil {
                Text(hint).font(.footnote).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var input: some View {
        if kind.isSecure && !reveals {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}
