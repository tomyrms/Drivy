import CoreLocation
import SwiftUI
import UIKit

/// Guided welcome at the first entry in a school (F21, AP172–AP174).
/// One question per screen, visible progress, and each screen says why it exists.
/// The screen shown follows the step confirmed by the server: nothing advances,
/// and nothing is marked done, before the school has answered.
///
/// Server step → screen: IDENTITY → « Bienvenue » then « Tes informations »
/// (staff: « Bienvenue » only), FORMATIONS → « Ta formation » / « Ton rôle »,
/// INFORMATION or DEVICE → « GPS pendant les leçons », REVIEW → « C’est prêt ».
struct SchoolOnboardingView: View {
    @Bindable var model: SchoolProfileWorkspace
    /// Trainings already read by the caller; only those of this learner in this school are shown.
    var trainings: [SchoolTraining] = []
    var loadsOnAppear = true
    var startsWithInformation = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var hasStarted = false
    @State private var editsInformation = false
    @State private var confirmsDiscard = false
    @State private var showsNotice = false
    @State private var location = SchoolOnboardingLocationPermission()

    private enum Screen: Hashable { case welcome, information, formation, gps, ready }

    var body: some View {
        NavigationStack {
            page
                .background(DrivyTheme.surface)
                .navigationTitle(model.school?.name ?? "Accueil")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom) { actionBar }
                .task {
                    if startsWithInformation { hasStarted = true }
                    if loadsOnAppear { await model.load() }
                }
                .confirmationDialog("Quitter sans enregistrer tes informations ?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                    Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
                } message: {
                    Text("Les étapes déjà confirmées par l’école restent enregistrées. Tu pourras reprendre plus tard.")
                }
                .sheet(isPresented: $showsNotice) { noticeSheet }
        }
        .tint(DrivyTheme.accent)
        .interactiveDismissDisabled(model.hasEdits || model.isBusy)
    }

    // MARK: - State

    private var isStaff: Bool { model.onboardingKind == .staff }
    private var isCompleted: Bool { model.onboarding?.status == "COMPLETED" }
    private var isWorking: Bool { model.isBusy || model.isLoading }
    private var gpsEnabled: Bool { model.school?.modules.gpsEnabled ?? false }
    private var schoolName: String { model.school?.name ?? "ton école" }
    private var timeZone: String { model.school?.timeZone ?? "Europe/Zurich" }

    private var screen: Screen? {
        guard let onboarding = model.onboarding else { return nil }
        if onboarding.status == "COMPLETED" { return editsInformation ? .information : .ready }
        switch onboarding.currentStep {
        case .identity: return isStaff || !hasStarted ? .welcome : .information
        case .formations: return .formation
        case .information, .device: return .gps
        case .review: return .ready
        }
    }
    private var steps: [Screen] {
        var value: [Screen] = isStaff ? [] : [.information]
        value.append(.formation)
        if gpsEnabled || screen == .gps { value.append(.gps) }
        value.append(.ready)
        return value
    }
    private var ownTrainings: [SchoolTraining] {
        guard let learnerID = model.learnerID else { return [] }
        return trainings.filter { $0.learnerId == learnerID && $0.schoolId == model.scope.schoolID }
    }
    private var blockers: [SchoolActionBlocker] {
        (model.onboarding?.pendingActions ?? []).filter { $0.code != "ONBOARDING_REVIEW_REQUIRED" }
    }

    // MARK: - Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.l) {
                if let screen, screen != .welcome, !editsInformation, let index = steps.firstIndex(of: screen) {
                    DrivyStepProgress(current: index + 1, total: steps.count)
                }
                statusBlock
                if let screen {
                    content(screen)
                } else if model.isLoading {
                    DrivyLoadingState(title: "Préparation de ton accueil…")
                } else if model.errorMessage == nil {
                    DrivyEmptyState(title: "Accueil indisponible",
                        message: "L’accueil de cette école ne peut pas être affiché pour le moment.",
                        symbol: "figure.wave", actionTitle: "Réessayer", action: { Task { await model.load() } })
                }
            }
            .drivyPageContent()
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var statusBlock: some View {
        if let error = model.errorMessage, !isWorking {
            SchoolErrorNotice(message: error, retry: { Task { await model.load() } })
        }
        if let pending = model.pending {
            DrivyPanel {
                DrivyPendingRequest(
                    message: "L’étape suivante sera possible après vérification du résultat.",
                    notes: pendingNotes(pending),
                    reference: pending.id,
                    verify: { Task { await model.verifyPending() } }, canVerify: model.canVerifyPending,
                    retry: model.canRetryPending ? { Task { await model.retryPending() } } : nil)
            }
        }
    }

    private func pendingNotes(_ pending: PendingSchoolCommand) -> [String] {
        var notes: [String] = []
        if !pending.kind.isProfile { notes.append("Cette demande vient d’un autre écran de l’école.") }
        if pending.scope != model.scope { notes.append("Tes accès ont changé depuis l’envoi. Le renvoi reste désactivé.") }
        return notes
    }

    @ViewBuilder private func content(_ screen: Screen) -> some View {
        switch screen {
        case .welcome: welcome
        case .information: information
        case .formation: formation
        case .gps: gps
        case .ready: ready
        }
    }

    // MARK: - Screens

    private var welcome: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xl) {
            hero(symbol: "figure.wave", title: "Bienvenue chez \(schoolName)")
            DrivyRowGroup {
                if isStaff {
                    DrivyEntityRow(title: "Ton rôle", leading: .symbol("person.badge.key"))
                } else {
                    DrivyEntityRow(title: "Tes informations", leading: .symbol("person.text.rectangle"))
                    DrivyEntityRow(title: "Ta formation", leading: .symbol("car"))
                }
                if gpsEnabled {
                    DrivyEntityRow(title: "Ton choix pour le GPS", leading: .symbol("location"))
                }
            }
        }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            stepTitle("Tes informations")
            if let profile = model.profile {
                VStack(alignment: .leading, spacing: DrivySpacing.l) {
                    nameField(.firstName, text: $model.draft.firstName, value: profile.firstName, identifier: "profile-first-name")
                        .textContentType(.givenName)
                    nameField(.lastName, text: $model.draft.lastName, value: profile.lastName, identifier: "profile-last-name")
                        .textContentType(.familyName)
                    if model.editableFields.contains(.contactEmail) {
                        DrivyGuidedTextField(label: "E-mail de contact", text: $model.draft.contactEmail,
                            note: note(.contactEmail), error: fieldError(.contactEmail), identifier: "profile-email")
                            .textContentType(.emailAddress).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                    }
                    if model.editableFields.contains(.contactPhone) {
                        DrivyGuidedTextField(label: "Téléphone", text: $model.draft.contactPhone,
                            note: note(.contactPhone), error: fieldError(.contactPhone), identifier: "profile-phone")
                            .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    }
                }
                .disabled(!model.canMutate)
                if let notice = model.notice, notice.status == "APPROVED" {
                    Button { showsNotice = true } label: {
                        Label("Comment l’école utilise tes données", systemImage: "doc.text")
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DrivyTheme.accent)
                }
            } else {
                DrivyInlineMessage(text: "Ton dossier n’est pas encore prêt chez \(schoolName). Tu peux continuer : l’école le préparera.",
                    tone: .neutral)
            }
        }
    }

    private var formation: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if isStaff {
                stepTitle("Ton rôle")
                DrivyPanel {
                    DrivyKeyValueRow(title: "Rôle dans l’école", value: SchoolPresentation.roles(model.roles))
                }
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if model.roles.contains("INSTRUCTOR") {
                        SchoolOnboardingPoint(symbol: "calendar", text: "Tes leçons apparaissent dans l’agenda dès que l’école les planifie.")
                    }
                    if model.roles.contains("ADMIN") {
                        SchoolOnboardingPoint(symbol: "desktopcomputer", text: "Gère l’école depuis l’espace web.")
                    }
                }
            } else {
                stepTitle("Ta formation")
                DrivyRowGroup {
                    if ownTrainings.isEmpty {
                        DrivyEntityRow(title: "\(schoolName) va ouvrir ta formation", leading: .symbol("car"))
                    } else {
                        ForEach(ownTrainings) { training in
                            DrivyEntityRow(title: "Permis \(training.categoryCode)",
                                meta: training.startedOn.map { "Depuis le \(SchoolPresentation.civilDate($0))" },
                                leading: .symbol("car"),
                                badge: training.status == "ACTIVE" ? nil : DrivyStatusBadge(title: SchoolPresentation.trainingStatus(training.status), tone: .neutral))
                        }
                    }
                    if let email = model.school?.contactEmail, !email.isEmpty {
                        DrivyEntityRow(title: "Contact de l’école", meta: email, leading: .symbol("envelope"))
                    }
                }
            }
        }
    }

    private var gps: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if !gpsEnabled {
                stepTitle("GPS pendant les leçons")
                Text("\(schoolName) n’enregistre pas de trajet pendant les leçons pour le moment.")
            } else if isStaff {
                stepTitle("GPS pendant les leçons")
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    SchoolOnboardingPoint(symbol: "hand.raised", text: "Enregistre le trajet avec l’accord de l’élève. Son choix reste modifiable.")
                    SchoolOnboardingPoint(symbol: "location", text: "Autorise la position sur cet appareil maintenant ou au début d’une leçon.")
                }
                locationStatus
            } else {
                stepTitle("GPS pendant les leçons")
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    SchoolOnboardingPoint(symbol: "location", text: "L’appareil du moniteur enregistre le trajet, avec ton accord.")
                    SchoolOnboardingPoint(symbol: "hand.raised", text: "Tu peux refuser ou modifier ton choix. La leçon reste possible sans trajet.")
                }
            }
        }
    }

    @ViewBuilder private var locationStatus: some View {
        if location.isDenied {
            VStack(alignment: .leading, spacing: DrivySpacing.s) {
                DrivyStatusBadge(title: "Position non autorisée", symbol: "location.slash", tone: .warning)
                Text("Les leçons restent possibles sans trajet. Tu pourras autoriser la position plus tard dans Réglages.")
                    .font(.footnote)
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var ready: some View {
        if isCompleted {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                hero(symbol: "checkmark.circle", title: "C’est prêt")
                if let success = model.successMessage, !model.hasEdits {
                    DrivyInlineMessage(text: success)
                }
                SchoolOnboardingPoint(symbol: "calendar", text: isStaff ? "Tes leçons apparaissent dans l’agenda dès que l’école les planifie."
                    : "Tes leçons et tes bilans apparaissent dans Drivy dès que l’école les prépare.")
            }
        } else if !blockers.isEmpty {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                hero(symbol: "list.bullet.clipboard", title: "Il reste à compléter")
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    ForEach(Array(blockers.enumerated()), id: \.offset) { _, blocker in
                        SchoolOnboardingPoint(symbol: "circle", text: blockerText(blocker))
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: DrivySpacing.xl) {
                hero(symbol: "checkmark.seal", title: "Tout est en ordre")
                DrivyPanel {
                    VStack(alignment: .leading, spacing: 0) {
                        if let profile = model.profile {
                            DrivyKeyValueRow(title: "Nom", value: fullName(profile))
                        }
                        if isStaff {
                            DrivyKeyValueRow(title: "Rôle", value: SchoolPresentation.roles(model.roles))
                        } else if !ownTrainings.isEmpty {
                            DrivyKeyValueRow(title: "Formation", value: ownTrainings.map { "Permis \($0.categoryCode)" }.joined(separator: ", "))
                        }
                        if gpsEnabled {
                            DrivyKeyValueRow(title: "GPS", value: gpsSummary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder private var actionBar: some View {
        if let screen {
            DrivyFormActionBar(hint: hint(screen).text, hintTone: hint(screen).tone) {
                actions(screen)
            }
        }
    }

    @ViewBuilder private func actions(_ screen: Screen) -> some View {
        switch screen {
        case .welcome:
            Button {
                if isStaff { save(.formations) } else { hasStarted = true }
            } label: { DrivyBusyLabel(title: "Commencer", isBusy: model.isBusy) }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(isStaff ? !model.canMutate : model.onboarding == nil)
            .accessibilityIdentifier("onboarding-start")
        case .information:
            Button(action: continueFromInformation) {
                DrivyBusyLabel(title: informationActionTitle, isBusy: isWorking)
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!canContinueInformation)
            .accessibilityIdentifier("profile-save")
        case .formation:
            Button { save(gpsEnabled ? .information : .review) } label: {
                DrivyBusyLabel(title: "Continuer", isBusy: isWorking)
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.canMutate)
            .accessibilityIdentifier("onboarding-continue")
        case .gps:
            gpsActions
        case .ready:
            readyActions
        }
    }

    @ViewBuilder private var gpsActions: some View {
        if gpsEnabled && isStaff && location.isUndetermined {
            Button { location.request() } label: { Text("Autoriser la position") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding-allow-location")
            Button { save(.review, skipping: ["DEVICE"]) } label: {
                DrivyBusyLabel(title: "Passer cette étape", isBusy: model.isBusy)
            }
            .buttonStyle(DrivySecondaryButtonStyle())
            .disabled(!model.canMutate)
            .accessibilityIdentifier("onboarding-skip-optional")
        } else {
            Button { save(.review) } label: {
                DrivyBusyLabel(title: "Continuer", isBusy: isWorking)
            }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.canMutate)
            .accessibilityIdentifier("onboarding-continue")
            if gpsEnabled && isStaff && location.isDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: { Text("Ouvrir Réglages") }
                .buttonStyle(DrivySecondaryButtonStyle())
            }
        }
    }

    @ViewBuilder private var readyActions: some View {
        if isCompleted {
            Button { dismiss() } label: { Text("Accéder à Drivy") }
                .buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(model.isBusy)
                .accessibilityIdentifier("onboarding-done")
            if model.profile != nil, !model.editableFields.isEmpty {
                Button { editsInformation = true } label: { Text("Modifier mes informations") }
                    .buttonStyle(DrivySecondaryButtonStyle())
                    .disabled(isWorking)
            }
        } else if blockers.contains(where: { $0.field != nil }) && model.profile != nil {
            Button {
                hasStarted = true
                save(.identity)
            } label: { DrivyBusyLabel(title: "Compléter mes informations", isBusy: isWorking) }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.canMutate)
        } else {
            Button {
                Task { if await model.completeOnboardingAfterConfirmation() { dismiss() } }
            } label: { DrivyBusyLabel(title: "Terminer l’accueil", isBusy: isWorking) }
            .buttonStyle(DrivyPrimaryButtonStyle())
            .disabled(!model.canMutate || !blockers.isEmpty)
            .accessibilityIdentifier("onboarding-complete")
        }
    }

    private func hint(_ screen: Screen) -> (text: String?, tone: DrivyTone) {
        if isWorking { return (nil, .neutral) }
        if model.pending != nil { return ("Vérifie d’abord la demande en attente, plus haut.", .neutral) }
        if model.school?.status == "ARCHIVED" { return ("Cette école est archivée : l’accueil ne peut plus être modifié.", .neutral) }
        if model.errorMessage != nil && !model.canMutate { return ("Réessaie plus haut pour continuer.", .danger) }
        switch screen {
        case .information:
            if model.profile != nil && !namesValid { return ("Renseigne ton prénom et ton nom pour continuer.", .neutral) }
            if model.hasEdits && !model.canSaveProfile { return ("Vérifie les informations signalées.", .neutral) }
            return (nil, .neutral)
        case .ready:
            if !isCompleted && !blockers.isEmpty && !(blockers.contains(where: { $0.field != nil }) && model.profile != nil) {
                return ("L’école doit d’abord préparer ton dossier. Tu pourras terminer ensuite.", .neutral)
            }
            return (nil, .neutral)
        case .welcome, .formation, .gps:
            return (nil, .neutral)
        }
    }

    private var namesValid: Bool {
        model.draft.isValid(allowed: model.editableFields.intersection([.firstName, .lastName]), timeZone: timeZone)
    }
    private var informationActionTitle: String {
        guard isCompleted else { return "Continuer" }
        return model.hasEdits ? "Enregistrer" : "Revenir"
    }
    private var canContinueInformation: Bool {
        if isCompleted && !model.hasEdits { return !model.isBusy }
        guard model.canMutate else { return false }
        guard model.profile != nil else { return true }
        return namesValid && (!model.hasEdits || model.canSaveProfile)
    }
    private func continueFromInformation() {
        if isCompleted && !model.hasEdits { editsInformation = false; return }
        guard canContinueInformation else { return }
        Task {
            if model.hasEdits {
                guard await model.saveProfileAfterConfirmation() else { return }
            }
            if isCompleted { editsInformation = false; return }
            _ = await model.saveOnboarding(step: .formations, skipping: [])
        }
    }
    private func save(_ step: SchoolOnboardingStep, skipping passed: Set<String> = []) {
        Task { _ = await model.saveOnboarding(step: step, skipping: passed) }
    }

    // MARK: - Navigation

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let action = backAction {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: action) {
                    Label("Retour", systemImage: "chevron.backward").labelStyle(.titleAndIcon)
                }
                .disabled(isWorking)
                .accessibilityIdentifier("onboarding-back")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(closeTitle) {
                if model.hasEdits { confirmsDiscard = true } else { dismiss() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("onboarding-later")
        }
    }

    private var closeTitle: String { isCompleted ? "Fermer" : "Plus tard" }

    /// Going back is a saved step too, so resuming on another device shows the same screen.
    private var backAction: (() -> Void)? {
        guard let screen else { return nil }
        if isCompleted {
            guard editsInformation else { return nil }
            return {
                if let profile = model.profile { model.draft = SchoolProfileDraft(profile) }
                editsInformation = false
            }
        }
        switch screen {
        case .welcome: return nil
        case .information: return { hasStarted = false }
        case .formation:
            guard model.canMutate else { return nil }
            return { hasStarted = true; save(.identity) }
        case .gps:
            guard model.canMutate else { return nil }
            return { save(.formations) }
        case .ready:
            guard model.canMutate else { return nil }
            return { save(gpsEnabled ? .information : .formations) }
        }
    }

    // MARK: - Helpers

    @ViewBuilder private func nameField(_ field: SchoolProfileField, text: Binding<String>, value: String?, identifier: String) -> some View {
        if model.editableFields.contains(field) {
            DrivyGuidedTextField(label: field.label, text: text, note: note(field), error: fieldError(field), identifier: identifier)
        } else {
            DrivyKeyValueRow(title: field.label, value: value ?? "Non renseigné")
        }
    }
    private func note(_ field: SchoolProfileField) -> String? {
        guard let rule = model.applicablePolicy?.fields.first(where: { $0.field == field }) else { return nil }
        return rule.requirement == .optional ? "Facultatif" : nil
    }
    private func fieldError(_ field: SchoolProfileField) -> String? {
        guard model.hasEdits, model.editableFields.contains(field),
              !model.draft.isValid(allowed: [field], timeZone: timeZone) else { return nil }
        switch field {
        case .firstName: return "Renseigne ton prénom (150 caractères au plus)."
        case .lastName: return "Renseigne ton nom (150 caractères au plus)."
        case .contactEmail: return "Vérifie l’adresse e-mail, par exemple nom@exemple.ch."
        case .contactPhone: return "Le téléphone est limité à 32 caractères."
        case .birthDate, .postalAddress, .profilePhotoDocumentId: return nil
        }
    }
    private func blockerText(_ blocker: SchoolActionBlocker) -> String {
        if let code = blocker.field, let field = SchoolProfileField(rawValue: code) {
            return "\(field.label) : \(blocker.message)"
        }
        return blocker.message
    }
    private func fullName(_ profile: SchoolAdministrativeProfile) -> String {
        let value = [profile.firstName, profile.lastName].compactMap { $0 }.joined(separator: " ")
        return value.isEmpty ? "Non renseigné" : value
    }
    private var gpsSummary: String {
        guard isStaff else { return "Facultatif, selon ton choix" }
        if location.isAuthorized { return "Position autorisée" }
        if location.isDenied { return "Position non autorisée" }
        return "À décider plus tard"
    }

    private var noticeSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DrivySpacing.m) {
                    if let notice = model.notice {
                        Text(notice.noticeText).textSelection(.enabled)
                        Text(notice.retentionText).textSelection(.enabled)
                        if let email = notice.contactEmail {
                            DrivyContactRow(title: "Contact pour tes données", value: email, symbol: "envelope")
                        }
                        Text("Version \(notice.version)")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(DrivyTheme.muted)
                    }
                }
                .font(.body)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .drivyPageContent()
            }
            .background(DrivyTheme.surface)
            .navigationTitle("Tes données")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fermer") { showsNotice = false } }
            }
        }
        .tint(DrivyTheme.accent)
    }

    /// Welcome and end of the flow answer each other: a brand plate, then the title. No sentence under it.
    private func hero(symbol: String, title: String) -> some View {
        SchoolOnboardingHero(symbol: symbol, title: title)
    }

    private func stepTitle(_ text: String) -> some View {
        Text(text).font(.drivyTitle).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
}

/// Entry point helper for the root: one read of AP172 (a GET creates nothing).
/// True only when the server confirms an unfinished welcome for this very
/// membership; any failure keeps the guided welcome closed.
enum SchoolOnboardingPrompt {
    @MainActor
    static func isPending(api: any SchoolProfileAPI, scope: SchoolCommandScope, kind: SchoolOnboardingKind) async -> Bool {
        guard let value = try? await api.onboarding(schoolID: scope.schoolID, kind: kind),
              value.schoolId == scope.schoolID, value.personId == scope.personID,
              value.membershipId == scope.membershipID else { return false }
        return value.status != "COMPLETED"
    }
}

/// Location permission of this device, asked only when the instructor taps
/// « Autoriser la position ». Never asked for a learner.
@MainActor @Observable
private final class SchoolOnboardingLocationPermission: NSObject, @preconcurrency CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus = .notDetermined
    @ObservationIgnored private let manager = CLLocationManager()
    var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    var isDenied: Bool { status == .denied || status == .restricted }
    var isUndetermined: Bool { status == .notDetermined }
    override init() { super.init(); status = manager.authorizationStatus; manager.delegate = self }
    func request() { status = manager.authorizationStatus; if status == .notDetermined { manager.requestWhenInUseAuthorization() } }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { status = manager.authorizationStatus }
}

/// Tête des écrans d’ouverture et de fin de l’accueil : pastille de symbole sur l’aplat de marque, puis le titre.
/// La pastille disparaît aux tailles d’accessibilité pour laisser la largeur au titre.
private struct SchoolOnboardingHero: View {
    let symbol: String
    let title: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var plate: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: DrivySpacing.l) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(DrivyTheme.accent)
                    .frame(width: plate, height: plate)
                    .background(DrivyTheme.accentSoft, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.drivyScreenTitle)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Un point explicatif d’un écran de l’accueil : pastille de symbole (même langage que les lignes de
/// l’écran d’ouverture), puis la phrase. La pastille disparaît aux tailles d’accessibilité.
private struct SchoolOnboardingPoint: View {
    let symbol: String
    let text: String
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var plate: CGFloat = 44

    var body: some View {
        HStack(alignment: .center, spacing: DrivySpacing.s) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(DrivyTheme.muted)
                    .frame(width: plate, height: plate)
                    .background(DrivyTheme.surfaceMuted, in: Circle())
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.body)
                .foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
