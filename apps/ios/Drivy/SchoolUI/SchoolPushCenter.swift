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
    @ObservationIgnored private(set) var deviceToken: String?
    /// Jeton accepté par l’école pour la session ouverte ; réenvoyé seulement s’il change.
    @ObservationIgnored private(set) var registeredToken: String?
    @ObservationIgnored private var hasSession = false
    /// Secret de révocation et jeton de l’appareil inscrit (#120).
    @ObservationIgnored private let revocations: any SchoolPushRevocationStoring
    /// Une seule révocation à la fois : une reprise au premier plan n’en empile pas une seconde.
    @ObservationIgnored private var isRevoking = false
    /// Trois secondes au plus pour une révocation : une fin de session n’attend pas un réseau absent.
    @ObservationIgnored private let revocationBudget: Duration
    /// État système lu sans rien demander, et demande d'inscription APNs : injectés pour les tests, jamais le système réel.
    @ObservationIgnored private let systemStatus: @MainActor () async -> UNAuthorizationStatus
    @ObservationIgnored private let registersForRemote: @MainActor () -> Void
    /// Génération de session : chaque début et chaque fin la font avancer. Une inscription lancée dans une génération
    /// qui n'est plus la courante ne marque jamais le jeton « enregistré » (#441).
    @ObservationIgnored private var sessionGeneration = 0
    /// Fin de la dernière inscription mise en file : les PUT de cet appareil ne se chevauchent jamais, donc l'ordre des
    /// réponses est l'ordre des validations côté école et le dernier secret reçu est le dernier secret valide.
    @ObservationIgnored private var registrationTail: Task<Void, Never>?

    init(revocations: any SchoolPushRevocationStoring = KeychainSchoolPushRevocationStore(),
         revocationBudget: Duration = .seconds(3),
         systemStatus: @escaping @MainActor () async -> UNAuthorizationStatus = {
             await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
         },
         registersForRemote: @escaping @MainActor () -> Void = { UIApplication.shared.registerForRemoteNotifications() }) {
        self.revocations = revocations
        self.revocationBudget = revocationBudget
        self.systemStatus = systemStatus
        self.registersForRemote = registersForRemote
    }

    func configure(client: SchoolNotificationClient?) { self.client = client }

    /// Relit l’état système sans rien demander.
    func refreshAuthorization() async {
        authorization = Self.authorization(await systemStatus())
        if authorization == .allowed, hasSession { registersForRemote() }
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
        hasSession = true; sessionGeneration += 1
        Task { await refreshAuthorization(); await upload() }
    }

    /// Fin de session, quelle qu’en soit la cause (#120) : déconnexion, restauration échouée, renouvellement refusé,
    /// échec du Trousseau. Révocation authentifiée tant qu’un jeton d’accès vaut ; sinon le secret rendu à
    /// l’enregistrement. Une panne réseau ne retient rien : la révocation reste à faire et reprend au prochain
    /// lancement ou au prochain retour au premier plan.
    func sessionEnding() async {
        SchoolNotificationSettingsCache.reset()
        SchoolReplayCache.shared.reset()
        hasSession = false; sessionGeneration += 1
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
    /// Les enregistrements passent un à un (file) : l'école fait tourner le secret à chaque PUT, et deux PUT en vol
    /// pourraient rendre leurs réponses dans l'ordre inverse de leur validation.
    /// Vrai seulement si l'école a répondu ET que le secret rendu est durablement conservé : sans sauvegarde, l'appareil
    /// ne se tient pas pour enregistré (un secret perdu rend la révocation anonyme impossible).
    @discardableResult
    func registerDevice(token: String) async -> Bool {
        await serialized { await self.putAndKeep(token: token) }
    }

    /// Inscrit le jeton courant s'il ne l'est pas déjà pour cette session. Deux déclenchements rapprochés (connexion et
    /// retour du jeton APNs) se fondent en un seul PUT : le second, passé son tour, trouve le jeton déjà enregistré.
    func upload() async {
        await serialized { await self.uploadIfNeeded() }
    }

    private func uploadIfNeeded() async {
        guard hasSession, authorization == .allowed, let token = deviceToken, token != registeredToken else { return }
        let generation = sessionGeneration
        guard await putAndKeep(token: token) else { return }
        // Session terminée (ou autre session ouverte) pendant l'enregistrement : le secret reste sur l'appareil, la
        // révocation reprendra hors session, mais ce jeton n'est pas « enregistré » pour la session suivante.
        guard hasSession, generation == sessionGeneration else { return }
        registeredToken = token
    }

    private func putAndKeep(token: String) async -> Bool {
        guard let client else { return false }
        do {
            let secret = try await client.register(token: token, environment: .current)
            if let secret {
                do { try revocations.save(SchoolPushRevocationRecord(token: token, secret: secret)) }
                catch { return false }
            } else if let recorded = try? revocations.load(), recorded.token == token {
                // L'école ne rend plus de secret : celui d'avant ne correspond plus à rien.
                try? revocations.clear()
            }
            return true
        } catch { return false }
    }

    /// File FIFO sur l'acteur principal : le travail suivant attend la fin du précédent, qu'il réussisse ou non.
    private func serialized<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        let previous = registrationTail
        let task = Task { @MainActor in
            await previous?.value
            return await work()
        }
        registrationTail = Task { _ = await task.value }
        return await task.value
    }

    /// Révocation d'un appareil : authentifiée d'abord, puis le secret de l'appareil quand l'école ne reconnaît plus
    /// la session. Chaque tentative est bornée. Tant qu'aucune réponse ne confirme la révocation, l'enregistrement
    /// reste au Trousseau : un essai de plus aura lieu à la prochaine transition, sans boucle.
    private func revoke(token: String) async {
        guard !isRevoking, let client else { return }
        isRevoking = true
        defer { isRevoking = false }
        // Le record visé est celui d'AVANT l'attente : ce qui sera effacé, c'est lui et rien d'autre (#441).
        let recorded = try? revocations.load()
        let target = recorded?.token == token ? recorded : nil
        let secret = target?.secret
        let authenticated = Task { try await client.revoke(token: token) }
        let deadline = Task { try? await Task.sleep(for: revocationBudget); authenticated.cancel() }
        var failure: Error?
        do { try await authenticated.value } catch { failure = error }
        deadline.cancel()
        if failure == nil {
            // Confirmée : le secret n’a plus d’usage.
            clearRecord(matching: target)
            return
        }
        // Une session sans jeton d’accès n’a plus que le secret pour se révoquer ; toute autre panne attendra.
        guard (failure as? SchoolPlanningFailure) == .unauthorized, let secret else { return }
        let anonymous = Task { try await client.revokeAnonymously(token: token, secret: secret) }
        let anonymousDeadline = Task { try? await Task.sleep(for: revocationBudget); anonymous.cancel() }
        var anonymousFailure: Error?
        do { try await anonymous.value } catch { anonymousFailure = error }
        anonymousDeadline.cancel()
        if anonymousFailure == nil { clearRecord(matching: target) }
    }

    /// Efface exactement le record que la révocation visait (jeton ET secret). Un record renouvelé pendant l'attente,
    /// même pour le même jeton, désigne un nouvel enregistrement que cette révocation ne couvre pas : il reste.
    private func clearRecord(matching target: SchoolPushRevocationRecord?) {
        guard let target, let current = try? revocations.load(), current == target else { return }
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
        // #103/#445 : conversation active, bas du fil affiché et rien ne le recouvre → lecture autorisée de la séquence
        // visée, puis pas de bannière en double. Si la lecture échoue, la séquence manque ou une feuille recouvre le fil,
        // l'alerte est présentée comme avant.
        if await MessagingActiveConversation.absorbs(notification.request.content.userInfo) { return [] }
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
