import Security
import SwiftUI
import UIKit
import UserNotifications

/// Secret de révocation d'un appareil push (#120) : rendu une seule fois à l'enregistrement, la base n'en garde que
/// l'empreinte. Il est conservé au Trousseau avec le jeton qu'il désigne, et effacé dès que l'école a confirmé la
/// révocation. Tant qu'un enregistrement existe, une révocation reste donc due : c'est ce que la reprise vérifie.
struct SchoolPushRevocationRecord: Codable, Equatable, Sendable {
    let version: Int
    let token: String
    let secret: String

    init(token: String, secret: String) {
        version = 1; self.token = token; self.secret = secret
    }

    var isValid: Bool {
        version == 1 && SchoolPushToken.valid(token) && SchoolPushRevocationSecret.valid(secret)
    }
}

/// Le Trousseau n'a pas accepté le secret : la révocation restera à faire, jamais de repli en clair.
struct SchoolPushRevocationStorageError: Error {}

@MainActor protocol SchoolPushRevocationStoring: AnyObject {
    func load() throws -> SchoolPushRevocationRecord?
    func save(_ record: SchoolPushRevocationRecord) throws
    func clear() throws
}

/// Un seul élément, dans le Trousseau de cet appareil : même classe d'accessibilité et même écriture relue que les
/// journaux d'intention (`SchoolCodeJoinJournal`), aucune synchronisation iCloud, aucun fichier en clair.
@MainActor final class KeychainSchoolPushRevocationStore: SchoolPushRevocationStoring {
    private let service: String
    private let account = "device-v1"
    private let maximumBytes = 4 * 1_024

    init(service: String = "ch.drivy.push-device-revocation.v1") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }

    func load() throws -> SchoolPushRevocationRecord? {
        var lookup = query
        lookup[kSecReturnData as String] = true; lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count <= maximumBytes,
              let record = try? JSONDecoder().decode(SchoolPushRevocationRecord.self, from: data), record.isValid else {
            throw SchoolPushRevocationStorageError()
        }
        return record
    }

    func save(_ record: SchoolPushRevocationRecord) throws {
        guard record.isValid, let data = try? JSONEncoder().encode(record), data.count <= maximumBytes else {
            throw SchoolPushRevocationStorageError()
        }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil) == errSecSuccess else {
                throw SchoolPushRevocationStorageError()
            }
        } else if status != errSecSuccess { throw SchoolPushRevocationStorageError() }
        // L'appareil ne retient que ce qu'il relit : une écriture non confirmée laisse la révocation à faire.
        guard try load() == record else { throw SchoolPushRevocationStorageError() }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SchoolPushRevocationStorageError() }
    }
}

/// Coffre en mémoire : tests et écrans de contrôle, qui n'écrivent aucun Trousseau.
@MainActor final class SchoolPushRevocationMemoryStore: SchoolPushRevocationStoring {
    private(set) var record: SchoolPushRevocationRecord?
    /// Simule un appareil qui ne peut rien conserver.
    var refusesToStore = false

    func load() throws -> SchoolPushRevocationRecord? { record }
    func save(_ record: SchoolPushRevocationRecord) throws {
        guard !refusesToStore, record.isValid else { throw SchoolPushRevocationStorageError() }
        self.record = record
    }
    func clear() throws { record = nil }
}

/// Notifications push des cours (#43, #44) et révocation de l'appareil (#120). L’autorisation système n’est demandée
/// qu’après un geste explicite (« Activer les notifications », « Prévenir des prochaines sessions ») ; jamais au lancement.
/// Le jeton d’appareil reste en mémoire ; le secret de révocation reste au Trousseau. Ni l’un ni l’autre n’est journalisé.
@MainActor @Observable final class SchoolPushCenter {
    static let shared = SchoolPushCenter()

    enum Authorization: Equatable { case unknown, notDetermined, denied, allowed }

    private(set) var authorization: Authorization = .unknown
    /// Série à ouvrir après un toucher sur une notification ; consommée par l’entrée des cours de l’élève.
    private(set) var pendingSeriesID: UUID?
    /// Conversation d’une alerte de messagerie touchée (#74) ; l’accueil change d’onglet, l’onglet Messages la consomme.
    private(set) var pendingMessagingTarget: MessagingNotificationTarget?
    @ObservationIgnored private(set) var client: SchoolNotificationClient?
    @ObservationIgnored private var deviceToken: String?
    /// Jeton accepté par l’école pour la session ouverte ; réenvoyé seulement s’il change.
    @ObservationIgnored private var registeredToken: String?
    @ObservationIgnored private var hasSession = false
    /// Secret de révocation et jeton de l’appareil inscrit (#120).
    @ObservationIgnored private let revocations: any SchoolPushRevocationStoring
    /// Une seule révocation à la fois : une reprise au premier plan n’en empile pas une seconde.
    @ObservationIgnored private var isRevoking = false
    /// Trois secondes au plus pour une révocation : une fin de session n’attend pas un réseau absent.
    @ObservationIgnored private let revocationBudget: Duration

    init(revocations: any SchoolPushRevocationStoring = KeychainSchoolPushRevocationStore(),
         revocationBudget: Duration = .seconds(3)) {
        self.revocations = revocations
        self.revocationBudget = revocationBudget
    }

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

    /// Fin de session, quelle qu’en soit la cause (#120) : déconnexion, restauration échouée, renouvellement refusé,
    /// échec du Trousseau. Révocation authentifiée tant qu’un jeton d’accès vaut ; sinon le secret rendu à
    /// l’enregistrement. Une panne réseau ne retient rien : la révocation reste à faire et reprend au prochain
    /// lancement ou au prochain retour au premier plan.
    func sessionEnding() async {
        SchoolNotificationSettingsCache.reset()
        SchoolReplayCache.shared.reset()
        hasSession = false
        pendingSeriesID = nil
        pendingMessagingTarget = nil
        let recorded = try? revocations.load()
        let token = registeredToken ?? deviceToken ?? recorded?.token
        registeredToken = nil
        guard let token else { return }
        await revoke(token: token)
    }

    /// Reprise d'une révocation restée à faire : un enregistrement conservé hors session désigne un appareil encore
    /// inscrit pour une session terminée, que la révocation ait échoué ou que l'app ait été arrêtée entre-temps.
    /// Un essai par transition, jamais pendant une session ouverte (`hasSession`), jamais pendant une restauration ou
    /// une connexion (`identityIsBusy`) : une session retrouvée ne révoque rien. Jamais de boucle.
    func resumePendingRevocation(identityIsBusy: Bool) async {
        guard !hasSession, !identityIsBusy, !isRevoking, let record = try? revocations.load() else { return }
        await revoke(token: record.token)
    }

    func didRegister(deviceToken data: Data) {
        guard let token = SchoolPushToken.hex(data) else { return }
        deviceToken = token
        Task { await upload() }
    }

    func didFailToRegister() { deviceToken = nil }

    func open(seriesID: UUID) { pendingSeriesID = seriesID }
    func open(messaging target: MessagingNotificationTarget) { pendingMessagingTarget = target }
    /// Rend la demande en attente et l’oublie : une seule ouverture par toucher.
    func consumePendingMessagingTarget() -> MessagingNotificationTarget? {
        defer { pendingMessagingTarget = nil }
        return pendingMessagingTarget
    }
    func consumePendingSeries() -> UUID? {
        defer { pendingSeriesID = nil }
        return pendingSeriesID
    }

    /// Enregistre l’appareil et garde le secret de révocation avec son jeton ; un nouvel enregistrement le remplace.
    /// Une école plus ancienne n’en rend pas : seule la révocation authentifiée reste possible, comme avant #120.
    @discardableResult
    func registerDevice(token: String) async -> Bool {
        guard let client else { return false }
        do {
            let secret = try await client.register(token: token, environment: .current)
            if let secret { try? revocations.save(SchoolPushRevocationRecord(token: token, secret: secret)) }
            return true
        } catch { return false }
    }

    private func upload() async {
        guard hasSession, authorization == .allowed, let token = deviceToken, token != registeredToken else { return }
        guard await registerDevice(token: token) else { return }
        // Session terminée pendant l'enregistrement : le secret reste sur l'appareil, la révocation reprendra hors
        // session, au lancement suivant ou au retour au premier plan.
        guard hasSession else { return }
        registeredToken = token
    }

    /// Révocation d'un appareil : authentifiée d'abord, puis le secret de l'appareil quand l'école ne reconnaît plus
    /// la session. Chaque tentative est bornée. Tant qu'aucune réponse ne confirme la révocation, l'enregistrement
    /// reste au Trousseau : un essai de plus aura lieu à la prochaine transition, sans boucle.
    private func revoke(token: String) async {
        guard !isRevoking, let client else { return }
        isRevoking = true
        defer { isRevoking = false }
        let recorded = try? revocations.load()
        let secret = recorded?.token == token ? recorded?.secret : nil
        let authenticated = Task { try await client.revoke(token: token) }
        let deadline = Task { try? await Task.sleep(for: revocationBudget); authenticated.cancel() }
        var failure: Error?
        do { try await authenticated.value } catch { failure = error }
        deadline.cancel()
        if failure == nil {
            // Confirmée : le secret n’a plus d’usage.
            clearRecord(for: token)
            return
        }
        // Une session sans jeton d’accès n’a plus que le secret pour se révoquer ; toute autre panne attendra.
        guard (failure as? SchoolPlanningFailure) == .unauthorized, let secret else { return }
        let anonymous = Task { try await client.revokeAnonymously(token: token, secret: secret) }
        let anonymousDeadline = Task { try? await Task.sleep(for: revocationBudget); anonymous.cancel() }
        var anonymousFailure: Error?
        do { try await anonymous.value } catch { anonymousFailure = error }
        anonymousDeadline.cancel()
        if anonymousFailure == nil { clearRecord(for: token) }
    }

    /// Efface le secret de ce jeton seulement : un enregistrement plus récent n’est jamais effacé par une révocation
    /// qui ne le concerne pas.
    private func clearRecord(for token: String) {
        let recorded = try? revocations.load()
        guard recorded == nil || recorded?.token == token else { return }
        try? revocations.clear()
    }

    static func authorization(_ status: UNAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .denied
        }
    }

    /// École et conversation de la charge `MESSAGING` (apps/api/src/messaging-notifications.ts) ; autre alerte : `nil`.
    nonisolated static func messagingTarget(in userInfo: [AnyHashable: Any], receivedAt: Date = Date()) -> MessagingNotificationTarget? {
        MessagingNotificationTarget(userInfo: userInfo, receivedAt: receivedAt)
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
        // #103 : conversation active, bas du fil affiché → le fil se met à jour, pas de bannière en double.
        if MessagingActiveConversation.suppresses(notification.request.content.userInfo) { return [] }
        return [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let userInfo = response.notification.request.content.userInfo
        // Alerte de messagerie (#74) : l’école et la conversation seulement, jamais de contenu.
        if let target = SchoolPushCenter.messagingTarget(in: userInfo) {
            await MainActor.run { SchoolPushCenter.shared.open(messaging: target) }
            return
        }
        guard let seriesID = SchoolPushCenter.seriesID(in: userInfo) else { return }
        await MainActor.run { SchoolPushCenter.shared.open(seriesID: seriesID) }
    }
}
