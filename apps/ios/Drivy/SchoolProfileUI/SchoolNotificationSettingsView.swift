import SwiftUI
import UIKit

/// Paramètres → Notifications : autorisation de l’appareil et préférences du compte.
struct SchoolNotificationSettingsView: View {
    @State private var model: SchoolNotificationSettingsModel
    /// Moniteur ou administration de l’école ouverte : seule condition pour voir les alertes d’équipe.
    let isStaff: Bool
    @State private var push = SchoolPushCenter.shared
    @Environment(\.scenePhase) private var scenePhase

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
                } header: { Text("Cours collectifs").drivyFormSectionHeader() }
                    .drivyFormRows()
            } else if model.errorMessage == nil {
                Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows()
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: DrivyLayout.formColumn)
        .frame(maxWidth: .infinity)
        .background(DrivyTheme.canvas)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .drivyFormRows()
    }

    private func toggle(_ title: String, _ category: SchoolNotificationCategory,
                        _ preferences: SchoolNotificationPreferences, id: String) -> some View {
        Toggle(title, isOn: Binding(get: { category.value(in: preferences) },
                                    set: { value in model.set(category, value) }))
            .drivyControlTint()
            .disabled(!model.isCurrent)
            .accessibilityValue((category.value(in: preferences) ? "Activé" : "Désactivé")
                                + (model.isPending(category) ? ", à synchroniser" : ""))
            .accessibilityIdentifier(id)
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
