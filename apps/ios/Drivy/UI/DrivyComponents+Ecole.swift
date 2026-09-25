import SwiftUI

// Shared anatomy of the app shell, the learners tab, the school tab and the
// school administration (catalogue, team, invitations, profile, configuration,
// joining a school). Built only from DrivyTheme tokens and shared components.

// MARK: - Shell toolbar

/// Leading item of every tab: the current school, which opens the school chooser.
/// The name is the context line of the mockups; under accessibility text sizes
/// only the symbol remains so the navigation bar never truncates the title.
struct DrivySchoolToolbarItem: ToolbarContent {
    let schoolName: String?
    let chooseSchool: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: chooseSchool) { DrivySchoolButtonLabel(schoolName: schoolName) }
                .accessibilityLabel("Changer d’école")
                .accessibilityValue(schoolName ?? "Aucune école choisie")
                .accessibilityIdentifier("choose-school")
        }
    }
}

/// Trailing item of every tab, always the last one on the trailing edge.
struct DrivyAccountToolbarItem: ToolbarContent {
    let openAccount: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openAccount) { Label("Compte", systemImage: "person.crop.circle") }
                .accessibilityIdentifier("school-account")
        }
    }
}

private struct DrivySchoolButtonLabel: View {
    let schoolName: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    private static let maxNameWidth: CGFloat = 200

    var body: some View {
        if let schoolName, !typeSize.isAccessibilitySize {
            HStack(spacing: DrivySpacing.xxs) {
                Text(schoolName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Self.maxNameWidth, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
        } else {
            Label(schoolName ?? "Écoles", systemImage: "building.2")
        }
    }
}

// MARK: - Entity rows

/// Leading visual of an entity row: initials for a person, a symbol otherwise.
enum DrivyRowLeading {
    case avatar(String)
    case symbol(String)
    case none
}

/// One anatomy for every list of people or records (learners, members,
/// invitations, catalogue entries): leading avatar or symbol, title, meta line,
/// status badge under the meta, optional chevron. Navigation containers that
/// draw their own chevron (List + NavigationLink) keep `showsChevron` false.
struct DrivyEntityRow: View {
    let title: String
    var meta: String? = nil
    var leading: DrivyRowLeading = .none
    var badge: DrivyStatusBadge? = nil
    var showsChevron = false
    var isSelected = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            if !typeSize.isAccessibilitySize { leadingView }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.text)
                if let meta, !meta.isEmpty {
                    Text(meta).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
                if let badge { badge.padding(.top, DrivySpacing.xxs) }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DrivyTheme.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, DrivySpacing.xs)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var leadingView: some View {
        switch leading {
        case .avatar(let name):
            DrivyAvatar(name: name, isSelected: isSelected)
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.muted)
                .frame(width: 44, height: 44)
                .background(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }
}

/// Read-only value with its label (contacts, invitation facts). Same leading
/// column as DrivyNavigationRow so values and actions align in one group.
struct DrivyContactRow: View {
    let title: String
    let value: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(title).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                Text(value)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, DrivySpacing.s)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Destructive row closing a group of actions (« Se déconnecter »).
/// Aligned on the DrivyNavigationRow symbol column, danger tone, 52 pt.
struct DrivyDestructiveRow: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            HStack(spacing: DrivySpacing.m) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title).font(.headline)
                Spacer(minLength: 0)
            }
            .foregroundStyle(DrivyTheme.danger)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DrivyRowButtonStyle())
    }
}

/// Full-width destructive action (revoking a link): the shared danger style.
typealias DrivyDestructiveButtonStyle = DrivyDangerButtonStyle

// MARK: - Forms

/// Context shown at the top of an administration form: the school or learner
/// concerned, then one sentence on what the form changes.
struct DrivyFormIntro: View {
    let context: String
    var message: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(context)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.muted)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Persistent label above a text field (the placeholder is never the label).
struct DrivyFormField: View {
    let label: String
    @Binding var text: String
    var prompt: String? = nil
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(label).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                .accessibilityHidden(true)
            TextField(prompt ?? label, text: $text)
                .accessibilityLabel(label)
                .accessibilityIdentifier(identifier ?? "")
        }
        .padding(.vertical, DrivySpacing.xxs)
    }
}

/// Success or warning inside a grouped Form (outside a Form, use DrivyInlineMessage).
struct DrivyFormMessage: View {
    let text: String
    var tone: DrivyTone = .success

    private var symbol: String {
        switch tone {
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        case .accent, .neutral: "info.circle.fill"
        }
    }

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(tone.foreground)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

/// Bottom bar holding the validation action of an administration form or
/// review sheet. A single line above the action explains why it is disabled,
/// or what failed, never with color alone.
struct DrivyFormActionBar<Actions: View>: View {
    let hint: String?
    let hintTone: DrivyTone
    let actions: Actions

    init(hint: String? = nil, hintTone: DrivyTone = .neutral, @ViewBuilder actions: () -> Actions) {
        self.hint = hint
        self.hintTone = hintTone
        self.actions = actions()
    }

    var body: some View {
        // Same bar as the agenda and report screens: one anatomy for every form.
        DrivyStickyActionBar {
            if let hint, !hint.isEmpty {
                Label(hint, systemImage: hintTone == .danger ? "exclamationmark.triangle.fill" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(hintTone == .neutral ? DrivyTheme.muted : hintTone.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
            }
            actions
        }
    }
}

/// Label of a button whose action writes to the school: a spinner and a
/// progress verb while busy, the action verb otherwise.
struct DrivyBusyLabel: View {
    let title: String
    var busyTitle = "Enregistrement…"
    let isBusy: Bool

    var body: some View {
        HStack(spacing: DrivySpacing.xs) {
            if isBusy { ProgressView().accessibilityHidden(true) }
            Text(isBusy ? busyTitle : title)
        }
    }
}

// MARK: - Uncertain request

/// The single presentation of a request whose result is not yet known
/// (network cut, uncertain answer). Same title, symbol, order and verbs on
/// every administration screen: what is kept, the check, the identical resend,
/// then the reference. In a Form it is the content of one Section; on a page it
/// sits in a DrivyPanel. Buttons use explicit styles so a Form row never
/// triggers several actions at once.
struct DrivyPendingRequest<Details: View>: View {
    let message: String
    let notes: [String]
    let reference: UUID?
    let verifyTitle: String
    let verify: (() -> Void)?
    let canVerify: Bool
    let verifyIdentifier: String?
    let retryTitle: String
    let retry: (() -> Void)?
    let canRetry: Bool
    let retryIdentifier: String?
    let details: Details

    init(message: String, notes: [String] = [], reference: UUID? = nil,
         verifyTitle: String = "Vérifier auprès de l’école", verify: (() -> Void)? = nil,
         canVerify: Bool = true, verifyIdentifier: String? = nil,
         retryTitle: String = "Renvoyer la même demande", retry: (() -> Void)? = nil,
         canRetry: Bool = true, retryIdentifier: String? = nil,
         @ViewBuilder details: () -> Details) {
        self.message = message
        self.notes = notes
        self.reference = reference
        self.verifyTitle = verifyTitle
        self.verify = verify
        self.canVerify = canVerify
        self.verifyIdentifier = verifyIdentifier
        self.retryTitle = retryTitle
        self.retry = retry
        self.canRetry = canRetry
        self.retryIdentifier = retryIdentifier
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            Label("Demande à vérifier", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(DrivyTheme.warning)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            details
            if let verify {
                Button(action: verify) { Text(verifyTitle) }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(!canVerify)
                    .accessibilityIdentifier(verifyIdentifier ?? "")
            }
            if let retry {
                Button(action: retry) {
                    Text(retryTitle)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canRetry ? DrivyTheme.accent : DrivyTheme.disabledText)
                .disabled(!canRetry)
                .accessibilityIdentifier(retryIdentifier ?? "")
            }
            if let reference {
                DisclosureGroup {
                    Text(reference.uuidString)
                        .font(.caption.monospaced())
                        .foregroundStyle(DrivyTheme.muted)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DrivySpacing.xxs)
                } label: {
                    Text("Référence de la demande").font(.footnote).foregroundStyle(DrivyTheme.muted)
                }
            }
        }
        .padding(.vertical, DrivySpacing.xxs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension DrivyPendingRequest where Details == EmptyView {
    init(message: String, notes: [String] = [], reference: UUID? = nil,
         verifyTitle: String = "Vérifier auprès de l’école", verify: (() -> Void)? = nil,
         canVerify: Bool = true, verifyIdentifier: String? = nil,
         retryTitle: String = "Renvoyer la même demande", retry: (() -> Void)? = nil,
         canRetry: Bool = true, retryIdentifier: String? = nil) {
        self.init(message: message, notes: notes, reference: reference,
                  verifyTitle: verifyTitle, verify: verify, canVerify: canVerify, verifyIdentifier: verifyIdentifier,
                  retryTitle: retryTitle, retry: retry, canRetry: canRetry, retryIdentifier: retryIdentifier,
                  details: { EmptyView() })
    }
}
