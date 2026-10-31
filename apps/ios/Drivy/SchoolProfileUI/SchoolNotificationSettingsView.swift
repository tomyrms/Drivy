import SwiftUI
import UIKit

/// Paramètres → Notifications : autorisation de l’appareil et préférences du compte.
struct SchoolNotificationSettingsView: View {
    @State private var model: SchoolNotificationSettingsModel
    /// Moniteur ou administration de l’école ouverte : seule condition pour voir les alertes d’équipe.
    let isStaff: Bool
    @State private var push = SchoolPushCenter.shared
    @State private var showsMessagingSettings = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.schoolMessagingEntry) private var messagingEntry

    init(client: SchoolNotificationClient, scope: AccountIntentScope, isStaff: Bool,
         contextIsCurrent: @escaping @MainActor () -> Bool) {
        _model = State(initialValue: SchoolNotificationSettingsCache.model(scope: scope, client: client,
                                                                           contextIsCurrent: contextIsCurrent))
        self.isStaff = isStaff
    }

    var body: some View {
        Form {
            authorizationSection
            if let message = model.errorMessage {
                Section {
                    DrivyFormMessage(text: message, tone: .danger)
                    Button(model.hasPendingChanges ? "Vérifier la synchronisation" : "Réessayer") {
                        Task { await model.retry() }
                    }
                    .disabled(model.isLoading || model.isSaving)
                    .accessibilityIdentifier("notification-preferences-retry")
                }
                    .drivyFormRows()
                    .accessibilityIdentifier("notification-preferences-error")
            }
            if let preferences = model.preferences {
                Section {
                    toggle("Places et nouvelles sessions", .courseOffers, preferences, id: "notification-course-offers")
                    toggle("Rappels de cours", .courseReminders, preferences, id: "notification-course-reminders")
                    toggle("Changements de cours", .courseChanges, preferences, id: "notification-course-changes")
                    if isStaff {
                        toggle("Alertes pour l’équipe", .courseStaffAlerts, preferences, id: "notification-course-staff-alerts")
                    }
                } header: {
                    Text("Cours collectifs · Toutes mes écoles").drivyFormSectionHeader()
                        .accessibilityLabel("Cours collectifs, préférences du compte pour toutes mes écoles")
                }
                    .drivyFormRows()
            } else if model.errorMessage == nil {
                Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows()
            }
            messagingSection
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsMessagingSettings) {
            if let makeSettingsView = messagingEntry?.makeSettingsView { makeSettingsView() }
        }
        .task {
            await push.refreshAuthorization()
            await model.load()
        }
        .refreshable { await model.load() }
        // Retour depuis Réglages : l’état système est relu.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await push.refreshAuthorization(); await model.load() } }
        }
        .onChange(of: model.isCurrent) { _, current in if !current { model.invalidate() } }
        .onChange(of: messagingEntry?.scopeID) { _, _ in showsMessagingSettings = false }
        .onChange(of: model.errorMessage) { _, message in
            if let message { UIAccessibility.post(notification: .announcement, argument: message) }
        }
    }

    @ViewBuilder private var authorizationSection: some View {
        Section {
            switch push.authorization {
            case .allowed:
                LabeledContent("Sur cet appareil", value: "Autorisées")
                    .accessibilityIdentifier("notification-authorization")
            case .denied:
                LabeledContent("Sur cet appareil", value: "Refusées")
                    .accessibilityIdentifier("notification-authorization")
                Button("Ouvrir Réglages") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
                .accessibilityIdentifier("notification-open-settings")
            case .notDetermined:
                Button("Activer les notifications") { Task { await push.requestAuthorization() } }
                    .accessibilityIdentifier("notification-request")
            case .unknown:
                DrivyLoadingState(title: "Chargement…")
            }
        } header: { Text("Cet appareil").drivyFormSectionHeader() }
        .drivyFormRows()
    }

    /// Les trois catégories de messagerie (#74) : seulement quand Messages est ouvert ici et que l'API les annonce,
    /// jamais pour des alertes qui n'existent pas.
    private var messagingPreferences: SchoolNotificationPreferences? {
        guard messagingEntry != nil, let preferences = model.preferences, preferences.supportsMessaging else { return nil }
        return preferences
    }

    private var messagingSection: some View {
        Section {
            if let preferences = messagingPreferences {
                toggle("Messages privés", .messagingPrivate, preferences, id: "notification-messaging-private")
                toggle("Messages du général", .messagingGeneral, preferences, id: "notification-messaging-general")
                toggle("Mentions", .messagingMentions, preferences, id: "notification-messaging-mentions")
            }
            DisclosureGroup("Notifications d’une conversation") {
                Text("La sourdine se règle dans les options de chaque conversation, dans Messages. L’autorisation de cet appareil reste distincte.")
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("notification-messaging-help")
            if messagingEntry?.makeSettingsView != nil {
                Button { showsMessagingSettings = true } label: {
                    HStack {
                        Text("Paramètres de Messages")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                    }
                }
                .accessibilityHint("Sauvegarde des clés et appareils de messagerie")
                .accessibilityIdentifier("notification-messaging-settings")
            } else {
                Text("Les paramètres de Messages ne sont pas disponibles ici.")
                    .foregroundStyle(DrivyTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            if messagingPreferences != nil {
                Text("Messages · Toutes mes écoles").drivyFormSectionHeader()
                    .accessibilityLabel("Messages, préférences du compte pour toutes mes écoles")
            } else {
                Text("Messages").drivyFormSectionHeader()
            }
        }
        .drivyFormRows()
    }

    private func toggle(_ title: String, _ category: SchoolNotificationCategory,
                        _ preferences: SchoolNotificationPreferences, id: String) -> some View {
        SchoolNotificationPreferenceRow(title: title,
            isOn: Binding(get: { category.value(in: preferences) }, set: { model.set(category, $0) }),
            status: model.synchronization(category), isCurrent: model.isCurrent, identifier: id)
    }
}

/// Le choix reste immédiat ; seul son retour réseau lent ajoute une ligne, sans flash de succès.
private struct SchoolNotificationPreferenceRow: View {
    let title: String
    @Binding var isOn: Bool
    let status: SchoolNotificationSyncStatus?
    let isCurrent: Bool
    let identifier: String
    @State private var showsPending = false

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
                Text(title)
                if let status, !status.isBriefPending || showsPending {
                    Label(status.title, systemImage: status.symbol)
                        .font(.caption)
                        .foregroundStyle(DrivyTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                }
            }
        }
        .drivyControlTint()
        .disabled(!isCurrent)
        .accessibilityValue((isOn ? "Activé" : "Désactivé") + (status.map { ", \($0.title)" } ?? ""))
        .accessibilityIdentifier(identifier)
        .task(id: status?.isBriefPending == true) {
            showsPending = false
            guard status?.isBriefPending == true else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            showsPending = true
        }
    }
}

/// La page Notifications des Paramètres, pour l’élève comme pour l’équipe : une seule page et un seul modèle, hors de
/// l’édition du profil (une saisie en cours n’en ferme plus l’accès). Absente sans service de notifications configuré.
struct SchoolNotificationSettingsDestination: View {
    let workspace: SchoolWorkspace

    @MainActor static func isAvailable(_ workspace: SchoolWorkspace) -> Bool {
        SchoolPushCenter.shared.client != nil && workspace.person != nil
    }

    var body: some View {
        if let client = SchoolPushCenter.shared.client, let personID = workspace.person?.personId {
            SchoolNotificationSettingsView(client: client,
                scope: AccountIntentScope(personID: personID, apiBaseURL: client.baseURL.absoluteString),
                isStaff: workspace.membership?.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) }) == true,
                contextIsCurrent: { workspace.person?.personId == personID && !workspace.requiresAuthentication && !workspace.accessRevoked })
        }
    }
}
