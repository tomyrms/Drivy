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

/// Le titre d’un écran-carte sans barre système (Aujourd’hui) : à la place et à la taille du titre de la barre,
/// posé sur la carte sans fond ni flou. Un léger halo de la couleur de page le garde lisible sur les rues ;
/// le bouton d’école reprend celui de la barre, dans sa capsule de verre.
struct DrivyFloatingTitleBar: View {
    let title: String
    var schoolName: String? = nil
    var chooseSchool: (() -> Void)? = nil

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(DrivyTheme.text)
            .lineLimit(1)
            .shadow(color: DrivyTheme.surface.opacity(0.9), radius: 4)
            .shadow(color: DrivyTheme.surface.opacity(0.6), radius: 10)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget)
            .overlay(alignment: .leading) {
                if let chooseSchool {
                    Button(action: chooseSchool) { DrivySchoolButtonLabel(schoolName: schoolName) }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Changer d’école")
                        .accessibilityValue(schoolName ?? "Aucune école choisie")
                        .accessibilityIdentifier("choose-school")
                }
            }
            .padding(.horizontal, DrivySpacing.m)
    }
}

/// Trailing item of every tab, always the last one on the trailing edge: the initials of the
/// signed-in person (`drivyAccountName` in the environment), the generic symbol otherwise.
struct DrivyAccountToolbarItem: ToolbarContent {
    let openAccount: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: openAccount) { DrivyAccountButtonLabel() }
                .accessibilityLabel("Compte")
                .accessibilityIdentifier("school-account")
        }
    }
}

extension EnvironmentValues {
    /// Display name of the signed-in person, for the account button.
    @Entry var drivyAccountName: String? = nil
}

private struct DrivyAccountButtonLabel: View {
    @Environment(\.drivyAccountName) private var name

    var body: some View {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DrivyAvatar(name: name, size: 32)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else {
            Label("Compte", systemImage: "person.crop.circle")
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
    /// Une personne avec sa photo autorisée, déjà lue ; les initiales tant qu’elle manque, sans changer la hauteur.
    case person(String, photo: Data?)
    case symbol(String)
    /// Catégorie de permis (`categoryCode`) : son véhicule dans la même pastille qu’un symbole.
    case license(String)
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
                // The status sits on the line of the name, after a middle dot: never a line of its own.
                if let badge, !typeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(DrivyTheme.text)
                            .lineLimit(1)
                        Text("·").font(.subheadline).foregroundStyle(DrivyTheme.muted).accessibilityHidden(true)
                        badge
                    }
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(DrivyTheme.text)
                    if let badge { badge }
                }
                if let meta, !meta.isEmpty {
                    Text(meta).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron { DrivyRowChevron() }
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
        case .person(let name, let photo):
            DrivyAvatar(name: name, isSelected: isSelected, photo: photo)
        case .symbol(let symbol):
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(isSelected ? DrivyTheme.accent : DrivyTheme.muted)
                .frame(width: DrivyLayout.tapTarget, height: DrivyLayout.tapTarget)
                .background(isSelected ? DrivyTheme.surfaceRaised : DrivyTheme.surfaceMuted, in: Circle())
                .accessibilityHidden(true)
        case .license(let code):
            DrivyLicenseTile(code: code, isSelected: isSelected)
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
    /// Same scaled column as DrivyNavigationRow: values and actions stay aligned at every text size.
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: symbolWidth)
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

/// Full-width destructive action (revoking a link): the shared danger style.
typealias DrivyDestructiveButtonStyle = DrivyDangerButtonStyle

// MARK: - Forms

extension View {
    /// Row fill of every native Form and List: the surface token, so rows never keep
    /// the system grey of dark mode on the canvas. Apply it to a Section or a row;
    /// a special fill (selection, danger, clear header) is set on its own row instead.
    func drivyFormRows(isSelected: Bool = false) -> some View {
        listRowBackground(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surfaceRaised)
            .environment(\.drivyRowContext, .grouped)
    }

    /// Tint of a system control that fills a shape under a white element: a switch track, the selected day of a
    /// date picker. It takes the fill blue, like the primary button; the ink blue of the system tint would put a
    /// white thumb or numeral on a pastel in dark. Light is unchanged: both blues share one light value.
    func drivyControlTint() -> some View {
        tint(DrivyTheme.accentFill)
    }

    /// A row that is not a cell: a header laid on the canvas (account heading), a notice or an empty state.
    func drivyClearRow() -> some View {
        listRowBackground(Color.clear)
    }

    /// Row fill of a plain, full-width list laid on a reading page: the row keeps the page
    /// color and only the hairlines separate entries; the selection keeps the soft accent.
    func drivyPlainRows(isSelected: Bool = false) -> some View {
        listRowBackground(isSelected ? DrivyTheme.accentSoft : DrivyTheme.surface)
    }

    /// Header of a native Form or List section: subheadline semibold, muted, in
    /// the written case (no system capitals). Apply it to the header Text.
    func drivyFormSectionHeader() -> some View {
        font(.subheadline.weight(.semibold))
            .foregroundStyle(DrivyTheme.muted)
            .textCase(nil)
    }
}

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
    /// Information requise encore vide : le point d’action précède le libellé jusqu’à la saisie.
    var isMissing = false
    var focus: FocusState<SchoolProfileField?>.Binding? = nil
    var focusValue: SchoolProfileField? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                if isMissing { DrivyActionDot().transition(.opacity) }
                Text(label).font(.subheadline).foregroundStyle(DrivyTheme.muted)
            }
            .accessibilityHidden(true)
            field
                .accessibilityLabel(label)
                // La valeur forcée remplaçait la saisie : VoiceOver annonçait un champ vide.
                .accessibilityValue(text.isEmpty ? (isMissing ? "À renseigner" : "") : text)
                .accessibilityIdentifier(identifier ?? "")
        }
        .padding(.vertical, DrivySpacing.xxs)
        .animation(DrivyMotion.feedback(reduceMotion), value: isMissing)
    }

    @ViewBuilder private var field: some View {
        if let focus, let focusValue {
            TextField(prompt ?? label, text: $text).focused(focus, equals: focusValue)
        } else {
            TextField(prompt ?? label, text: $text)
        }
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
        let ink = tone.quiet
        return Label {
            Text(text).foregroundStyle(ink == .neutral ? DrivyTheme.text : ink.foreground)
        } icon: {
            Image(systemName: symbol).foregroundStyle(ink.foreground)
        }
            .font(.subheadline)
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
    let maxWidth: CGFloat
    let actions: Actions

    init(hint: String? = nil, hintTone: DrivyTone = .neutral, maxWidth: CGFloat = DrivyLayout.formColumn,
         @ViewBuilder actions: () -> Actions) {
        self.hint = hint
        self.hintTone = hintTone
        self.maxWidth = maxWidth
        self.actions = actions()
    }

    var body: some View {
        // Same bar as the agenda and report screens: one anatomy for every form.
        DrivyStickyActionBar(maxWidth: maxWidth) {
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
    /// Offert seulement quand l’école a répondu ne pas connaître la demande : l’abandon est alors sans risque.
    let abandon: (() -> Void)?
    let canAbandon: Bool
    let details: Details
    @State private var confirmsAbandon = false

    init(message: String, notes: [String] = [], reference: UUID? = nil,
         verifyTitle: String = "Vérifier auprès de l’école", verify: (() -> Void)? = nil,
         canVerify: Bool = true, verifyIdentifier: String? = nil,
         retryTitle: String = "Renvoyer la même demande", retry: (() -> Void)? = nil,
         canRetry: Bool = true, retryIdentifier: String? = nil,
         abandon: (() -> Void)? = nil, canAbandon: Bool = true,
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
        self.abandon = abandon
        self.canAbandon = canAbandon
        self.details = details()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            // L’abandon n’est offert qu’après la réponse de l’école : le titre dit alors l’état connu.
            Label(abandon == nil ? "Demande à vérifier" : "Demande non enregistrée", systemImage: "clock.arrow.circlepath")
                .font(.headline)
                .foregroundStyle(DrivyTheme.text)
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
                        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canRetry ? DrivyTheme.accent : DrivyTheme.disabledText)
                .disabled(!canRetry)
                .accessibilityIdentifier(retryIdentifier ?? "")
            }
            if let abandon {
                Button(role: .destructive) { confirmsAbandon = true } label: {
                    Text("Abandonner la demande")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canAbandon ? DrivyTheme.danger : DrivyTheme.disabledText)
                .disabled(!canAbandon)
                .accessibilityIdentifier("pending-request-abandon")
                .confirmationDialog("Abandonner cette demande ?", isPresented: $confirmsAbandon, titleVisibility: .visible) {
                    Button("Abandonner la demande", role: .destructive) { abandon() }
                    Button("Conserver", role: .cancel) { }
                } message: { Text("Elle est retirée de cet appareil et ne sera pas envoyée à l’école.") }
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
         canRetry: Bool = true, retryIdentifier: String? = nil,
         abandon: (() -> Void)? = nil, canAbandon: Bool = true) {
        self.init(message: message, notes: notes, reference: reference,
                  verifyTitle: verifyTitle, verify: verify, canVerify: canVerify, verifyIdentifier: verifyIdentifier,
                  retryTitle: retryTitle, retry: retry, canRetry: canRetry, retryIdentifier: retryIdentifier,
                  abandon: abandon, canAbandon: canAbandon,
                  details: { EmptyView() })
    }
}
