import SwiftUI
import UIKit
import UserNotifications

/// Notifications push des cours (#43, #44). L’autorisation système n’est demandée qu’après un geste explicite
/// (« Activer les notifications », « Prévenir des prochaines sessions ») ; jamais au lancement.
/// Le jeton d’appareil reste en mémoire : il n’est ni écrit sur disque ni journalisé.
@MainActor @Observable final class SchoolPushCenter {
    static let shared = SchoolPushCenter()

    enum Authorization: Equatable { case unknown, notDetermined, denied, allowed }

    private(set) var authorization: Authorization = .unknown
    /// Série à ouvrir après un toucher sur une notification ; consommée par l’entrée des cours de l’élève.
    private(set) var pendingSeriesID: UUID?
    @ObservationIgnored private(set) var client: SchoolNotificationClient?
    @ObservationIgnored private var deviceToken: String?
    /// Jeton accepté par l’école pour la session ouverte ; réenvoyé seulement s’il change.
    @ObservationIgnored private var registeredToken: String?
    @ObservationIgnored private var hasSession = false

    private init() {}

    func configure(client: SchoolNotificationClient?) { self.client = client }

    /// Relit l’état système sans rien demander.
    func refreshAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorization = Self.authorization(settings.authorizationStatus)
        if authorization == .allowed, hasSession { UIApplication.shared.registerForRemoteNotifications() }
    }

    /// Geste explicite de la personne : seule voie vers la demande système.
    @discardableResult func requestAuthorization() async -> Bool {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return authorization == .allowed }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    /// Connexion confirmée : l’appareil s’enregistre si l’autorisation existe déjà, sans la demander.
    func sessionStarted() {
        hasSession = true
        Task { await refreshAuthorization(); await upload() }
    }

    /// Avant la déconnexion, tant que le jeton d’accès vaut encore : l’école cesse d’envoyer à cet appareil.
    /// Une panne n’empêche jamais la déconnexion ; l’école révoque d’elle-même un jeton refusé par Apple.
    func sessionEnding() async {
        hasSession = false
        pendingSeriesID = nil
        guard let token = registeredToken ?? deviceToken, let client else { registeredToken = nil; return }
        registeredToken = nil
        // Trois secondes au plus : la déconnexion n’attend pas un réseau absent.
        let revoke = Task { try? await client.revoke(token: token) }
        let deadline = Task { try? await Task.sleep(for: .seconds(3)); revoke.cancel() }
        await revoke.value
        deadline.cancel()
    }

    func didRegister(deviceToken data: Data) {
        guard let token = SchoolPushToken.hex(data) else { return }
        deviceToken = token
        Task { await upload() }
    }

    func didFailToRegister() { deviceToken = nil }

    func open(seriesID: UUID) { pendingSeriesID = seriesID }
    func consumePendingSeries() -> UUID? {
        defer { pendingSeriesID = nil }
        return pendingSeriesID
    }

    private func upload() async {
        guard hasSession, authorization == .allowed, let token = deviceToken, token != registeredToken, let client else { return }
        do {
            try await client.register(token: token, environment: .current)
            if hasSession { registeredToken = token }
        } catch {}
    }

    static func authorization(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    /// `seriesId` de la charge utile envoyée par apps/api/src/course-push.ts ; absent ou invalide : rien à ouvrir.
    nonisolated static func seriesID(in userInfo: [AnyHashable: Any]) -> UUID? {
        (userInfo["seriesId"] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// Relais UIKit : jeton APNs et toucher sur une notification.
@MainActor final class DrivyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        SchoolPushCenter.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        SchoolPushCenter.shared.didFailToRegister()
    }

    /// App ouverte : la notification reste visible, le bandeau des places proposées se relit de son côté.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let seriesID = SchoolPushCenter.seriesID(in: response.notification.request.content.userInfo) else { return }
        await MainActor.run { SchoolPushCenter.shared.open(seriesID: seriesID) }
    }
}
