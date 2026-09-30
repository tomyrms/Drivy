import SwiftUI

struct SchoolJoinView: View {
    @Bindable var model: SchoolJoinWorkspace
    let openSchool: (SchoolMembership) -> Void
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @State private var expandsRetention = false
    @FocusState private var linkFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    // First read only: later operations show their progress in the action itself.
                    if model.isBusy && !model.isReady {
                        DrivyLoadingState(title: "Vérification de ton compte…")
                    }
                    if let error = model.errorMessage, model.preview == nil, !isEntering {
                        SchoolErrorNotice(message: error, retry: model.isReady ? nil : { Task { await model.load() } })
                    }
                    if model.isConfirmed { confirmed }
                    else if model.isPending { pending }
                    else if let preview = model.preview { invitation(preview) }
                    else { linkEntry }
                }
                .drivyPageContent(maxWidth: DrivyLayout.compactColumn)
            }
            .background(DrivyTheme.surface)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) { primaryAction }
            .navigationTitle("Rejoindre une école")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }.disabled(model.isBusy)
                }
            }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.isBusy)
        .task { if loadsOnAppear { await model.load() } }
        .accessibilityIdentifier("join-school")
    }

    /// Entry state: the field is on screen, so a refused link is said under it.
    private var isEntering: Bool {
        model.isReady && model.preview == nil && !model.isPending && !model.isConfirmed
    }

    /// Same anatomy as the code field: permanent label, field, error under it, paste.
    private var linkEntry: some View {
        let error = isEntering ? model.errorMessage : nil
        return VStack(alignment: .leading, spacing: DrivySpacing.s) {
            SchoolJoinFieldBlock(label: "Lien d’invitation", error: error) {
                TextField("Coller le lien reçu", text: $model.link,
                          prompt: Text("Coller le lien reçu").foregroundStyle(DrivyTheme.muted))
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .keyboardType(.URL).textContentType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.go).onSubmit { Task { await model.inspect() } }
                    .focused($linkFocused)
                    .schoolJoinFieldChrome(hasError: error != nil, isFocused: linkFocused, minHeight: 64)
                    .disabled(model.isBusy || !model.isReady)
                    .accessibilityLabel("Lien d’invitation")
                    .accessibilityHint(error ?? "")
                    .accessibilityIdentifier("join-invitation-link")
            }
            PasteButton(payloadType: String.self) { values in
                if let value = values.first, value.utf8.count <= 2_048 { model.link = value }
            }
            .accessibilityLabel("Coller le lien")
            .frame(minHeight: 44)
            .disabled(model.isBusy || !model.isReady)
        }
    }

    private func invitation(_ preview: SchoolJoinPreview) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            schoolSummary(preview)
            Divider().overlay(DrivyTheme.border)
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                Text("Tes données dans l’école")
                    .font(.drivySection)
                    .foregroundStyle(DrivyTheme.text)
                    .accessibilityAddTraits(.isHeader)
                Text(preview.notice.noticeText)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Conservation des données", isExpanded: $expandsRetention) {
                    Text(preview.notice.retentionText).textSelection(.enabled).padding(.top, DrivySpacing.s)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DrivyContactRow(title: "Contact de l’école", value: preview.notice.contactEmail, symbol: "envelope")
            }
            Divider().overlay(DrivyTheme.border)
            Toggle(isOn: $model.acknowledgesNotice) {
                Text("J’ai pris connaissance de cette notice et je souhaite rejoindre l’école avec les rôles affichés.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("join-acknowledge")
            .fixedSize(horizontal: false, vertical: true)
            secondaryLink("Utiliser un autre lien") { model.anotherInvitation() }
        }
    }

    private func secondaryLink(_ title: String, action: @escaping () -> Void) -> some View {
        SchoolJoinTextLink(title: title, isBusy: model.isBusy, action: action)
    }

    private func schoolSummary(_ preview: SchoolJoinPreview) -> some View {
        var facts = [
            SchoolJoinFact(symbol: "person.crop.circle", text: SchoolPresentation.roles(preview.roles), isEmphasized: true),
            SchoolJoinFact(symbol: "envelope", text: preview.maskedEmail),
        ]
        if !model.isConfirmed {
            facts.append(SchoolJoinFact(symbol: "clock",
                text: "Valable jusqu’au \(SchoolTrainingFormatting.instant(preview.expiresAt, zone: TimeZone.current.identifier))"))
        }
        return SchoolJoinSchoolHeader(name: preview.schoolName, facts: facts, isConfirmed: model.isConfirmed)
    }

    private var pending: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyPanel {
                DrivyPendingRequest(
                    message: "La réponse de l’école n’est pas arrivée. Ta demande est conservée sur cet appareil.",
                    retry: { Task { await model.retry() } }, canRetry: !model.isBusy)
            }
        }
    }

    private var confirmed: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if let preview = model.preview { schoolSummary(preview) }
            DrivyInlineMessage(text: "Tu as rejoint l’école.")
            if model.trainingNotOpened {
                DrivyInlineMessage(text: "Ton école doit encore ouvrir ta formation.", tone: .neutral)
            }
            if let member = model.member {
                Text("Accès actuel : \(SchoolPresentation.roles(member.roles))")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Actualise tes accès pour ouvrir l’école.")
                    .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            secondaryLink("Consulter une autre invitation") { model.anotherInvitation() }
        }
    }

    private var actionHint: (text: String?, tone: DrivyTone) {
        if let error = model.errorMessage, model.preview != nil { return (error, .danger) }
        if model.preview != nil && !model.isConfirmed && !model.isPending && !model.acknowledgesNotice && !model.isBusy {
            return ("Confirme ta lecture de la notice pour rejoindre l’école.", .neutral)
        }
        return (nil, .neutral)
    }

    private var primaryAction: some View {
        let hint = actionHint
        return DrivyFormActionBar(hint: hint.text, hintTone: hint.tone) {
            if model.isConfirmed {
                if let member = model.member {
                    Button("Ouvrir mon école") { openSchool(member) }.disabled(model.isBusy)
                } else {
                    Button { Task { await model.verify() } } label: {
                        DrivyBusyLabel(title: "Actualiser mes accès", busyTitle: "Vérification…", isBusy: model.isBusy)
                    }
                    .disabled(model.isBusy)
                }
            } else if model.isPending {
                Button { Task { await model.verify() } } label: {
                    DrivyBusyLabel(title: "Vérifier auprès de l’école", busyTitle: "Vérification…", isBusy: model.isBusy)
                }
                .disabled(model.isBusy)
            } else if model.preview != nil {
                Button { Task { await model.accept() } } label: {
                    DrivyBusyLabel(title: "Rejoindre l’école", busyTitle: "Envoi…", isBusy: model.isBusy)
                }
                .disabled(!model.canAccept).accessibilityIdentifier("join-confirm")
            } else {
                Button { Task { await model.inspect() } } label: {
                    DrivyBusyLabel(title: "Continuer", busyTitle: "Vérification…", isBusy: model.isBusy && model.isReady)
                }
                .disabled(!model.canPreview).accessibilityIdentifier("join-preview")
            }
        }
        .buttonStyle(DrivyPrimaryButtonStyle())
        .frame(maxWidth: DrivyLayout.compactColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.surface)
    }
}

// MARK: - Éléments communs aux parcours « code » et « lien »

/// Ligne de fait sous le nom de l’école : symbole et texte, identiques dans les deux parcours.
struct SchoolJoinFact: Identifiable {
    let symbol: String
    let text: String
    var isEmphasized = false
    var id: String { symbol + text }
}

/// Tête de l’aperçu d’une école : pastille de symbole, nom, faits. Une seule anatomie pour le code et le lien.
struct SchoolJoinSchoolHeader: View {
    let name: String
    let facts: [SchoolJoinFact]
    /// Once joined, the mark turns into the success tone: the result is read before the sentence.
    var isConfirmed = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var plate: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var factSymbol: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.s) {
            HStack(spacing: DrivySpacing.s) {
                if !typeSize.isAccessibilitySize {
                    Image(systemName: isConfirmed ? "checkmark" : "building.2")
                        .font(isConfirmed ? Font.title2.weight(.semibold) : Font.title2)
                        .foregroundStyle(isConfirmed ? DrivyTheme.success : DrivyTheme.accent)
                        .frame(width: plate, height: plate)
                        .background(isConfirmed ? DrivyTheme.successSurface : DrivyTheme.accentSoft, in: Circle())
                        .accessibilityHidden(true)
                }
                Text(name)
                    .font(.drivyTitle)
                    .foregroundStyle(DrivyTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: DrivySpacing.xs) {
                ForEach(facts) { fact in
                    // One symbol column: the texts of the facts start on the same vertical line.
                    HStack(alignment: .firstTextBaseline, spacing: DrivySpacing.xs) {
                        Image(systemName: fact.symbol)
                            .frame(width: factSymbol)
                            .accessibilityHidden(true)
                        Text(fact.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(fact.isEmphasized ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(fact.isEmphasized ? DrivyTheme.text : DrivyTheme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Action texte des écrans pour rejoindre une école : même taille, même teinte, cible de 44 pt.
struct SchoolJoinTextLink: View {
    let title: String
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(SchoolJoinTextLinkStyle())
        .foregroundStyle(isBusy ? DrivyTheme.disabledText : DrivyTheme.accent)
        .disabled(isBusy)
    }
}

/// Retour d’appui de l’action texte : même échelle que les boutons, ancrée au bord du texte.
private struct SchoolJoinTextLinkStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? DrivyPress.scale : 1, anchor: .leading)
            .animation(DrivyMotion.press(reduceMotion), value: configuration.isPressed)
    }
}

/// Libellé permanent, champ, puis l’erreur sous le champ : le même bloc pour le code et le lien.
struct SchoolJoinFieldBlock<Field: View>: View {
    let label: String
    let error: String?
    var errorIdentifier: String? = nil
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xs) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DrivyTheme.text)
                .accessibilityHidden(true)
            field
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(DrivyTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(error)
                    .accessibilityIdentifier(errorIdentifier ?? "")
            }
        }
    }
}

/// Cadre d’un champ de saisie d’invitation : creux sur `canvas`, contour de contrôle,
/// contour d’accent quand le champ a le focus, de danger quand il est refusé.
private struct SchoolJoinFieldChrome: ViewModifier {
    let hasError: Bool
    let isFocused: Bool
    let minHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DrivyRadius.field, style: .continuous)
        content
            .padding(.horizontal, DrivySpacing.m)
            .frame(minHeight: minHeight)
            .background(hasError ? DrivyTheme.dangerSurface : DrivyTheme.canvas, in: shape)
            .overlay {
                shape.strokeBorder(hasError ? DrivyTheme.danger : (isFocused ? DrivyTheme.accent : DrivyTheme.controlBorder),
                                   lineWidth: hasError || isFocused ? 2 : 1)
            }
            .animation(DrivyMotion.feedback(reduceMotion), value: isFocused)
            .animation(DrivyMotion.feedback(reduceMotion), value: hasError)
    }
}

extension View {
    func schoolJoinFieldChrome(hasError: Bool, isFocused: Bool, minHeight: CGFloat) -> some View {
        modifier(SchoolJoinFieldChrome(hasError: hasError, isFocused: isFocused, minHeight: minHeight))
    }
}
