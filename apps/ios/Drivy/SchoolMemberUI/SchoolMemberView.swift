import SwiftUI
import UIKit

enum SchoolMemberEntryMode { case team, addLearner }

struct SchoolMemberView: View {
    @Bindable var model: SchoolMemberWorkspace
    @Bindable var identity: IdentitySession
    var mode: SchoolMemberEntryMode = .team
    let openInvitations: () -> Void
    let openLearner: (SchoolLearner) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editor: MemberEditorRoute?

    private struct MemberEditorRoute: Identifiable {
        let id: UUID
        let model: SchoolMemberWorkspace
    }

    private var listedMembers: [SchoolMember] { mode == .addLearner ? model.availableForLearnerRole : model.filteredMembers }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    DrivyFormIntro(context: model.school?.name ?? "Votre école",
                        message: mode == .addLearner ? "Choisissez un membre de l’école ou invitez une nouvelle personne."
                            : "Rôles et autorisations de chaque membre de l’école.")
                }.listRowBackground(DrivyTheme.canvas)
                if model.isLoading { Section { ProgressView("Ouverture des membres…").frame(maxWidth: .infinity, minHeight: 44) } }
                if let error = model.errorMessage {
                    Section {
                        SchoolErrorNotice(message: error,
                            retry: model.accessRevoked || model.isBusy || model.isLoading ? nil : { Task { await model.load() } })
                    }
                }
                if let success = model.successMessage { Section { DrivyFormMessage(text: success) } }
                if model.pending != nil { SchoolMemberPendingSection(model: model, identity: identity) }
                if mode == .addLearner {
                    Section {
                        Button(action: openInvitations) {
                            Label("Inviter un nouvel élève", systemImage: "envelope.badge.person.crop")
                        }
                        .buttonStyle(DrivySecondaryButtonStyle())
                        .disabled(model.isBusy || identity.isWorking)
                    } footer: {
                        Text("La personne accepte l’invitation avec son propre compte. Son dossier est ensuite créé, sans formation automatique.")
                    }
                }
                Section(mode == .addLearner ? "Ajouter le rôle Élève à un membre" : "Membres") {
                    ForEach(listedMembers) { member in
                        Button {
                            model.select(member, addLearner: mode == .addLearner)
                            guard model.selectedMember?.id == member.id else { return }
                            editor = MemberEditorRoute(id: member.id, model: model)
                        } label: { memberRow(member) }
                        .buttonStyle(.plain).disabled(model.isBusy || identity.isWorking)
                        .accessibilityIdentifier("school-member-\(member.id.uuidString)")
                    }
                    if listedMembers.isEmpty && !model.isLoading && model.errorMessage == nil {
                        if model.search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            DrivyEmptyState(title: mode == .addLearner ? "Aucun membre à ajouter" : "Aucun membre accessible",
                                message: mode == .addLearner ? "Invitez une nouvelle personne pour l’ajouter comme élève." : "Les membres de l’école apparaîtront ici.",
                                symbol: "person.2")
                        } else {
                            DrivyEmptyState(title: "Aucun résultat", message: "Aucun membre ne correspond à votre recherche.",
                                symbol: "magnifyingglass", actionTitle: "Effacer la recherche", action: { model.search = "" })
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .frame(maxWidth: 800).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
            .searchable(text: $model.search, prompt: "Rechercher une personne")
            .navigationTitle(mode == .addLearner ? "Ajouter un élève" : "Équipe et accès")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy || identity.isWorking) } }
            .task { await model.load() }
            .sheet(item: $editor, onDismiss: { model.clearSelection() }) { route in
                SchoolMemberEditor(model: route.model, identity: identity, memberID: route.id)
            }
            .onChange(of: model.locatedLearner?.id) { _, _ in
                if let learner = model.locatedLearner { openLearner(learner) }
            }
        }
        .interactiveDismissDisabled(model.isBusy || identity.isWorking)
        .tint(DrivyTheme.accent)
    }
    private func memberRow(_ member: SchoolMember) -> some View {
        DrivyEntityRow(title: member.displayName,
            meta: SchoolPresentation.roles(member.roles) + (member.id == model.scope.membershipID && member.status == "ACTIVE" ? " · votre compte" : ""),
            leading: .avatar(member.displayName),
            badge: member.status != "ACTIVE" ? DrivyStatusBadge(title: "Accès révoqué", symbol: "lock", tone: .warning) : nil,
            showsChevron: true)
    }
}

private struct SchoolMemberEditor: View {
    @Bindable var model: SchoolMemberWorkspace
    @Bindable var identity: IdentitySession
    let memberID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var presenter: UIViewController?
    @State private var authError: String?
    @State private var confirmsClose = false
    @State private var confirmsReload = false
    @State private var confirmsOwnAdminRemoval = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            Form {
                if let member = model.selectedMember, member.id == memberID {
                    Section {
                        HStack(spacing: DrivySpacing.m) {
                            if !typeSize.isAccessibilitySize { DrivyAvatar(name: member.displayName, size: 52) }
                            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                                Text(member.displayName).font(.drivyTitle).foregroundStyle(DrivyTheme.text)
                                Text(SchoolPresentation.roles(member.roles)).font(.subheadline).foregroundStyle(DrivyTheme.muted)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        if member.status != "ACTIVE" {
                            DrivyFormMessage(text: "Cet accès est révoqué. Une invitation reste nécessaire pour rejoindre à nouveau l’école.", tone: .warning)
                        }
                    }
                    .listRowBackground(DrivyTheme.canvas)
                    accessFields
                    if member.roles.contains("LEARNER") {
                        Section {
                            Button { Task { await model.findLearner(for: member) } } label: {
                                Label("Ouvrir le dossier élève", systemImage: "person.text.rectangle")
                            }.disabled(model.isBusy || identity.isWorking)
                        } footer: { Text("Les formations et les affectations de moniteurs se gèrent depuis ce dossier.") }
                    }
                } else {
                    Section {
                        DrivyEmptyState(title: "Membre indisponible",
                            message: "Cette personne n’est plus accessible. Fermez cet écran et actualisez les membres.",
                            symbol: "person.crop.circle.badge.questionmark")
                    }
                }
                if let error = model.errorMessage { Section { SchoolErrorNotice(message: error) } }
                if let authError { Section { SchoolErrorNotice(message: authError) } }
                if let success = model.successMessage, !model.hasUnsavedChanges { Section { DrivyFormMessage(text: success) } }
                if model.pending != nil { SchoolMemberPendingSection(model: model, identity: identity) }
                if model.ownAccessChanged {
                    Section { DrivyFormMessage(text: "Vos accès ont changé. Fermez cet écran pour ouvrir votre école avec les nouveaux droits.", tone: .accent) }
                } else if model.selectedMember?.id == memberID, model.selectedMember?.status == "ACTIVE" {
                    Section {
                        TextField("Expliquez pourquoi ces accès changent", text: $model.reason, axis: .vertical).lineLimit(3...6)
                            .accessibilityLabel("Motif du changement d’accès")
                            .disabled(!model.canMutate || identity.isWorking)
                        if model.reason.unicodeScalars.count > 800 {
                            Text("\(model.reason.unicodeScalars.count)/1 000 caractères").font(.caption)
                                .foregroundStyle(model.reason.unicodeScalars.count > 1000 ? DrivyTheme.danger : DrivyTheme.muted)
                        }
                        if model.needsReload { Button("Recharger et relire les accès") { confirmsReload = true }.disabled(model.isBusy || identity.isWorking) }
                    } header: { Text("Motif du changement") }
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if !model.ownAccessChanged, model.selectedMember?.id == memberID, model.selectedMember?.status == "ACTIVE" {
                    confirmationBar
                }
            }
            .navigationTitle("Rôles et autorisations").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        if model.hasUnsavedChanges { confirmsClose = true } else { dismiss() }
                    }.disabled(model.isBusy || identity.isWorking)
                }
            }
            .background(MemberAuthenticationPresenter { presenter = $0 }.frame(width: 0, height: 0))
            .confirmationDialog("Fermer sans enregistrer ?", isPresented: $confirmsClose, titleVisibility: .visible) {
                Button("Abandonner les modifications", role: .destructive) { dismiss() }
                Button("Continuer", role: .cancel) { }
            } message: { Text("Une demande déjà transmise reste conservée jusqu’à vérification.") }
            .confirmationDialog("Recharger les accès actuels ?", isPresented: $confirmsReload, titleVisibility: .visible) {
                Button("Recharger") { Task { await model.load() } }
                Button("Continuer la saisie", role: .cancel) { }
            } message: { Text("Les modifications du formulaire seront remplacées par la version de l’école. Une demande en attente reste conservée.") }
            .confirmationDialog("Retirer votre rôle Administration ?", isPresented: $confirmsOwnAdminRemoval, titleVisibility: .visible) {
                Button("Continuer avec la réauthentification", role: .destructive) { authenticateAndSave() }
                Button("Conserver mes accès", role: .cancel) { }
            } message: { Text("Vous ne pourrez plus administrer cette école après l’enregistrement.") }
        }
        .interactiveDismissDisabled(model.hasUnsavedChanges || model.isBusy || identity.isWorking)
        .tint(DrivyTheme.accent)
    }
    private var confirmationHint: (text: String, tone: DrivyTone) {
        if let authError { return (authError, .danger) }
        if let error = model.errorMessage { return (error, .danger) }
        if model.isChanged && model.roles.isEmpty { return ("Conservez au moins un rôle.", .neutral) }
        if model.isChanged && model.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ("Indiquez le motif du changement.", .neutral) }
        if model.reason.unicodeScalars.count > 1000 { return ("Le motif est limité à 1 000 caractères.", .neutral) }
        return ("Une nouvelle connexion à votre compte confirmera ce changement.", .neutral)
    }

    private var confirmationBar: some View {
        let hint = confirmationHint
        return DrivyFormActionBar(hint: hint.text, hintTone: hint.tone) {
            Button {
                if model.removesOwnAdmin { confirmsOwnAdminRemoval = true }
                else { authenticateAndSave() }
            } label: {
                DrivyBusyLabel(title: "Confirmer les accès",
                    busyTitle: identity.isWorking ? "Confirmation d’identité…" : "Enregistrement…",
                    isBusy: identity.isWorking || model.isBusy)
            }.buttonStyle(DrivyPrimaryButtonStyle())
                .disabled(!model.canSave || model.selectedMember?.id != memberID || identity.isWorking || presenter == nil)
                .accessibilityIdentifier("member-confirm-access")
        }
    }
    private var accessFields: some View {
        Group {
            Section {
                ForEach(SchoolMemberRole.allCases) { role in
                    Toggle(isOn: roleBinding(role.rawValue)) {
                        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                            Text(role.label).font(.headline)
                            Text(role.explanation).font(.footnote).foregroundStyle(DrivyTheme.muted)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DrivySpacing.xxs)
                    }
                    .disabled(!model.canMutate || identity.isWorking || model.selectedMember?.status != "ACTIVE" || (role == .admin && model.isLastAdministrator))
                }
                if model.isLastAdministrator { DrivyFormMessage(text: "L’école doit conserver au moins un administrateur actif.", tone: .neutral) }
            } header: { Text("Rôles dans cette école") }
            footer: { Text("Le rôle Moniteur ne donne accès qu’aux formations explicitement affectées. Ajouter Élève ouvre un dossier minimal, sans créer de formation.") }
            Section {
                ForEach(SchoolMemberGrant.allCases) { grant in
                    Toggle(grant.label, isOn: Binding(get: { model.grants.contains(grant.rawValue) }, set: { selected in
                        if selected { model.grants.insert(grant.rawValue) } else { model.grants.remove(grant.rawValue) }
                    })).disabled(!model.canMutate || identity.isWorking || model.selectedMember?.status != "ACTIVE")
                }
            } header: { Text("Autorisations particulières") }
            footer: { Text("Ces autorisations complètent les rôles. Elles ne créent ni affectation ni droit d’accès à une autre école.") }
        }
    }
    private func roleBinding(_ role: String) -> Binding<Bool> {
        Binding(get: { model.roles.contains(role) }, set: { selected in
            if selected { model.roles.insert(role) } else { model.roles.remove(role) }
        })
    }
    private func authenticateAndSave() {
        guard let presenter, model.canSave, model.selectedMember?.id == memberID else { return }
        authError = nil
        Task {
            let authenticated = await identity.reauthenticate(presenting: presenter, expectedPersonID: model.scope.personID)
            if authenticated { _ = await model.saveAfterReauthentication() }
            else { authError = identity.errorMessage }
        }
    }
}

private struct SchoolMemberPendingSection: View {
    @Bindable var model: SchoolMemberWorkspace
    @Bindable var identity: IdentitySession
    @State private var presenter: UIViewController?
    @State private var authError: String?
    var body: some View {
        Section {
            DrivyPendingRequest(message: "Vérifiez le résultat avant de modifier à nouveau les accès.",
                reference: model.pending?.id,
                verify: { Task { await model.verify() } },
                canVerify: !model.isBusy && !identity.isWorking,
                retryTitle: "Confirmer mon identité et renvoyer",
                retry: model.canRetry ? { retryAfterReauthentication() } : nil,
                canRetry: !identity.isWorking && presenter != nil,
                details: { requestedChange })
            if let authError { SchoolErrorNotice(message: authError) }
        }
        .background(MemberAuthenticationPresenter { presenter = $0 }.frame(width: 0, height: 0))
    }
    private func retryAfterReauthentication() {
        guard let presenter else { return }
        Task {
            if await identity.reauthenticate(presenting: presenter, expectedPersonID: model.scope.personID) {
                _ = await model.retryAfterReauthentication()
            } else { authError = identity.errorMessage }
        }
    }
    @ViewBuilder private var requestedChange: some View {
        if let command = model.pending, command.kind == .updateMember,
           let body = try? JSONDecoder().decode(MemberPendingReview.self, from: command.body) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                if let member = model.members.first(where: { $0.id == command.resourceID }) {
                    Text(member.displayName).font(.headline).foregroundStyle(DrivyTheme.text)
                }
                Text("Rôles demandés : \(SchoolPresentation.roles(body.roles))").font(.subheadline).foregroundStyle(DrivyTheme.text)
                Text(body.reason).font(.footnote).foregroundStyle(DrivyTheme.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
    private struct MemberPendingReview: Decodable { let roles: [String]; let reason: String }
}

private struct MemberAuthenticationPresenter: UIViewControllerRepresentable {
    let resolve: @MainActor (UIViewController) -> Void
    func makeUIViewController(context: Context) -> Anchor {
        let controller = Anchor(); controller.resolve = resolve; return controller
    }
    func updateUIViewController(_ controller: Anchor, context: Context) { controller.resolve = resolve }
    final class Anchor: UIViewController {
        var resolve: (@MainActor (UIViewController) -> Void)?
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); resolve?(self) }
    }
}
