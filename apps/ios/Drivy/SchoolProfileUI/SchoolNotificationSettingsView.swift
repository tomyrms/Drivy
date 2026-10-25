import SwiftUI
import UIKit

/// Préférences lues et écrites par l’école ; aucun interrupteur n’est montré avant la lecture.
@MainActor @Observable final class SchoolNotificationSettingsModel {
    let client: SchoolNotificationClient
    private(set) var preferences: SchoolNotificationPreferences?
    private(set) var isLoading = false
    private(set) var isSaving = false
    var errorMessage: String?

    init(client: SchoolNotificationClient) { self.client = client }

    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true; defer { isLoading = false }
        do { preferences = try await client.preferences(); errorMessage = nil }
        catch is CancellationError {}
        catch { errorMessage = Self.message(error) }
    }

    /// L’interrupteur ne bascule qu’après la réponse de l’école ; un conflit relit les préférences.
    func set(_ key: WritableKeyPath<SchoolNotificationPreferences, Bool>, _ value: Bool) async {
        guard var edit = preferences, !isSaving, edit[keyPath: key] != value else { return }
        isSaving = true; errorMessage = nil
        edit[keyPath: key] = value
        do {
            preferences = try await client.save(edit.body, version: edit.version)
            isSaving = false
        } catch is CancellationError {
            isSaving = false
        } catch {
            isSaving = false
            errorMessage = Self.message(error)
            if error as? SchoolPlanningFailure == .conflict {
                let kept = errorMessage
                await load()
                errorMessage = kept
            }
        }
    }

    static func message(_ error: any Error) -> String {
        if error as? SchoolPlanningFailure == .conflict { return "Tes préférences ont changé ailleurs. Vérifie-les." }
        return (error as? LocalizedError)?.errorDescription ?? "L’école n’a pas pu répondre."
    }
}

/// Mon profil → Notifications : autorisation de l’appareil et préférences du compte.
struct SchoolNotificationSettingsView: View {
    @State private var model: SchoolNotificationSettingsModel
    /// Moniteur ou administration de l’école ouverte : seule condition pour voir les alertes d’équipe.
    let isStaff: Bool
    @State private var push = SchoolPushCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    init(client: SchoolNotificationClient, isStaff: Bool) {
        _model = State(initialValue: SchoolNotificationSettingsModel(client: client))
        self.isStaff = isStaff
    }

    var body: some View {
        Form {
            authorizationSection
            if let message = model.errorMessage {
                Section { DrivyFormMessage(text: message, tone: .danger) }
                    .drivyFormRows()
                    .accessibilityIdentifier("notification-preferences-error")
            }
            if let preferences = model.preferences {
                Section {
                    toggle("Places et nouvelles sessions", \.courseOffers, preferences, id: "notification-course-offers")
                    toggle("Rappels de cours", \.courseReminders, preferences, id: "notification-course-reminders")
                    toggle("Changements de cours", \.courseChanges, preferences, id: "notification-course-changes")
                    if isStaff {
                        toggle("Alertes pour l’équipe", \.courseStaffAlerts, preferences, id: "notification-course-staff-alerts")
                    }
                } header: { Text("Cours collectifs").drivyFormSectionHeader() }
                    .drivyFormRows()
            } else if model.errorMessage == nil {
                Section { DrivyLoadingState(title: "Chargement…") }.drivyFormRows()
            } else {
                Section { Button("Réessayer") { Task { await model.load() } } }.drivyFormRows()
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
            if phase == .active { Task { await push.refreshAuthorization() } }
        }
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

    private func toggle(_ title: String, _ key: WritableKeyPath<SchoolNotificationPreferences, Bool>,
                        _ preferences: SchoolNotificationPreferences, id: String) -> some View {
        Toggle(title, isOn: Binding(get: { preferences[keyPath: key] },
                                    set: { value in Task { await model.set(key, value) } }))
            .drivyControlTint()
            .disabled(model.isSaving)
            .accessibilityIdentifier(id)
    }
}
