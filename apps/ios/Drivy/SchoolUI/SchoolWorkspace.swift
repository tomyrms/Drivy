import Foundation
import Observation

/// Authorized projections and protected personal intentions. Changing account or school drops all
/// school data synchronously; a late response never restores the old context.
@MainActor
@Observable
final class SchoolWorkspace {
    private(set) var confirmedPerson: SchoolPerson?
    private(set) var membership: SchoolMembership?
    private(set) var school: SchoolDetails?
    private(set) var confirmedLearners: [SchoolLearner] = []
    /// Le dossier du compte connecté reste distinct de l’annuaire et de ses recherches.
    private(set) var confirmedOwnLearner: SchoolLearner?
    private(set) var ownLearnerError: String?
    /// Les dossiers actifs de toute l’école auxquels manque une information requise, pour l’administration ;
    /// `nil` tant que rien n’a été lu. Le point de l’onglet Élèves s’y lit, quelles que soient la recherche et les
    /// pages affichées.
    private(set) var learnersToComplete: Set<UUID>?
    private(set) var confirmedLearner: SchoolLearner?
    private(set) var trainings: [SchoolTraining] = []
    private(set) var selectedLearnerID: UUID?
    private(set) var searchText = ""
    /// Seulement les dossiers dont le profil est à compléter (#153) : un filtre du serveur, jamais de la page chargée.
    private(set) var showsIncompleteProfilesOnly = false
    private(set) var nextLearnersCursor: String?
    private(set) var nextTrainingsCursor: String?

    private(set) var isLoadingAccount = false
    private(set) var isLoadingSchool = false
    private(set) var isRefreshingEntry = false
    private(set) var isSearching = false
    private(set) var isLoadingMoreLearners = false
    private(set) var isLoadingLearner = false
    private(set) var isLoadingTrainings = false
    private(set) var isLoadingMoreTrainings = false
    private(set) var requiresAuthentication = false
    /// Signed in, but the identity belongs to no school yet: joining with a code is the way in.
    private(set) var identityNotLinked = false
    /// The school refused this account (session expired, access withdrawn, identity not linked).
    /// A network failure never sets it: an ongoing trip keeps recording.
    private(set) var accessRevoked = false

    private(set) var accountError: String?
    private(set) var schoolError: String?
    private(set) var learnersError: String?
    private(set) var learnerError: String?
    private(set) var trainingsError: String?

    @ObservationIgnored private let api: any SchoolAPI
    @ObservationIgnored private var accountRequest = UUID()
    @ObservationIgnored private var accountRefresh = UUID()
    @ObservationIgnored private var schoolScope = UUID()
    @ObservationIgnored private var searchRequest = UUID()
    @ObservationIgnored private var ownLearnerRequest = UUID()
    @ObservationIgnored private var learnerRequest = UUID()
    @ObservationIgnored private var trainingsRequest = UUID()
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var learnerCursors: Set<String> = []
    @ObservationIgnored private var trainingCursors: Set<String> = []
    @ObservationIgnored private var accountReadAt: Date?
    @ObservationIgnored private var learnersReadAt: Date?
    @ObservationIgnored private var ownLearnerReadAt: Date?
    @ObservationIgnored private var awaitsManagementReturn = false

    @ObservationIgnored private let accountIntentBaseURL: URL?
    @ObservationIgnored private let selfIntentStore: (any SchoolSelfProfileIntentStore)?
    @ObservationIgnored private var selfIntentScope: AccountIntentScope?
    @ObservationIgnored private var selfWriteTail: Task<Void, Never>?
    private var selfIntents = SchoolSelfProfileIntents()
    private(set) var selfProfileIntentError: String?

    init(api: any SchoolAPI, accountIntentBaseURL: URL? = nil,
         selfIntentStore: (any SchoolSelfProfileIntentStore)? = nil) {
        self.api = api; self.accountIntentBaseURL = accountIntentBaseURL
        self.selfIntentStore = selfIntentStore ?? (accountIntentBaseURL == nil ? nil : EncryptedSchoolSelfProfileIntentStore())
    }

    /// Projection de la personne connectée, sans inventer une version ni des droits.
    var person: SchoolPerson? {
        guard let current = confirmedPerson else { return nil }
        return SchoolPerson(personId: current.personId, version: current.version,
            displayName: pendingSelfProfileEdit?.displayName ?? current.displayName,
            locale: current.locale, memberships: current.memberships)
    }
    var selfProfile: SchoolSelfProfile? {
        guard let base = confirmedSelfProfile else { return nil }
        return pendingSelfProfileEdit.map { SchoolSelfProfileIntent.projecting($0, on: base) } ?? base
    }
    var learners: [SchoolLearner] { confirmedLearners.map(projectedLearner) }
    var learner: SchoolLearner? { confirmedLearner.map(projectedLearner) }
    var ownLearner: SchoolLearner? { confirmedOwnLearner.map(projectedLearner) }
    var pendingSelfProfileEdit: SchoolSelfProfileEdit? { selfIntents.fields?.edit }
    var pendingSelfPhotoChoice: SchoolSelfPhotoIntent? { selfIntents.photo?.photoChoice }
    var hasPendingSelfProfile: Bool { !selfIntents.isEmpty }
    var profileAccountBaseURL: URL? { accountIntentBaseURL }

    func displayName(for personID: UUID) -> String? {
        personID == person?.personId ? person?.displayName : nil
    }

    private func projectedLearner(_ value: SchoolLearner) -> SchoolLearner {
        guard value.personId == confirmedPerson?.personId else { return value }
        let edit: SchoolSelfProfileEdit
        if let pending = pendingSelfProfileEdit { edit = pending }
        else if let profile = confirmedSelfProfile, profile.version >= (confirmedPerson?.version ?? 0) {
            edit = SchoolSelfProfileEdit(profile)
        } else { return value }
        return SchoolLearner(id: value.id, schoolId: value.schoolId, personId: value.personId, version: value.version,
            displayName: edit.displayName, contactEmail: edit.contactEmail.isEmpty ? nil : edit.contactEmail,
            contactPhone: edit.contactPhone.isEmpty ? nil : edit.contactPhone, archivedAt: value.archivedAt,
            profileReadiness: value.profileReadiness, profilePhotoDocumentId: value.profilePhotoDocumentId)
    }

    var entryDestination: SchoolEntryDestination {
        .resolve(schoolStatus: school?.status, roles: membership?.roles)
    }

    func reset() {
        SchoolTrainingModelCache.reset()
        accountRequest = UUID()
        accountRefresh = UUID()
        confirmedPerson = nil
        selfIntentScope = nil; selfIntents = SchoolSelfProfileIntents(); selfProfileIntentError = nil
        selfWriteTail = nil
        confirmedSelfProfile = nil
        selfPhoto = nil
        peoplePhotos = [:]
        accountError = nil
        requiresAuthentication = false
        identityNotLinked = false
        accessRevoked = false
        accountReadAt = nil
        isLoadingAccount = false
        awaitsManagementReturn = false
        clearSchool()
    }

    /// Lecture du compte. Quand un compte est déjà chargé et n’a pas été refusé, la relecture est silencieuse :
    /// rien n’est effacé à l’écran (une feuille ouverte, un dossier, un trajet en cours restent en place) et seul un
    /// changement de droits recharge l’école. Sinon (première lecture, accès refusé, déconnexion), tout repart de zéro.
    func loadAccount() async {
        if confirmedPerson != nil, !accessRevoked, !isLoadingAccount {
            await refreshAccount(minimumInterval: 0)
            return
        }
        await loadAccountFromScratch()
    }

    private func loadAccountFromScratch() async {
        let preferredSchool = membership?.schoolId
        reset()
        let request = accountRequest
        isLoadingAccount = true
        do {
            let result = try await api.me()
            guard request == accountRequest else { return }
            applyAccount(result)
            try? restoreSelfIntents()
            accountReadAt = Date()
            isLoadingAccount = false
            if let preferred = result.memberships.first(where: { $0.schoolId == preferredSchool }) {
                await selectSchool(preferred)
            } else if result.memberships.count == 1, let only = result.memberships.first {
                await selectSchool(only)
            }
        } catch {
            guard request == accountRequest else { return }
            isLoadingAccount = false
            if !invalidateAccess(for: error) { accountError = blockingMessage(for: error) }
        }
    }

    /// Return to the app: re-read the account without clearing anything on screen, at most
    /// every five minutes. Only a change of rights in the current school reloads it; a network
    /// failure changes nothing, a refusal from the school closes the account as any read does.
    @discardableResult
    func refreshAccount(minimumInterval: TimeInterval = 300, now: Date = Date()) async -> Bool {
        guard let current = confirmedPerson, !isLoadingAccount else { return false }
        if let accountReadAt, now.timeIntervalSince(accountReadAt) < minimumInterval { return true }
        let request = accountRequest
        let previousReadAt = accountReadAt
        accountRefresh = UUID()
        let refresh = accountRefresh
        accountReadAt = now
        do {
            let result = try await api.me()
            // Several screens can request a silent refresh at once. Only the latest
            // reading may replace the account and its rights, even within one session.
            guard request == accountRequest, refresh == accountRefresh else { return false }
            guard result.personId == current.personId else { await loadAccountFromScratch(); return confirmedPerson != nil && !accessRevoked }
            applyAccount(result)
            try? restoreSelfIntents()
            guard let selected = membership else {
                if result.memberships.count == 1, let only = result.memberships.first { await selectSchool(only) }
                return true
            }
            guard let updated = result.memberships.first(where: { $0.schoolId == selected.schoolId }) else {
                // No longer a member of this school.
                clearSchool()
                if result.memberships.count == 1, let only = result.memberships.first { await selectSchool(only) }
                return true
            }
            if updated.membershipId != selected.membershipId || updated.accessEpoch != selected.accessEpoch
                || Set(updated.roles) != Set(selected.roles) || Set(updated.grants) != Set(selected.grants) {
                await selectSchool(updated)
            } else if updated != selected {
                // Same rights (a renamed school): the projection changes, nothing is reloaded.
                membership = updated
            }
            return true
        } catch {
            guard request == accountRequest, refresh == accountRefresh else { return false }
            // Une panne passagère ne compte pas comme une lecture : la prochaine occasion réessaie.
            if !invalidateAccess(for: error) { accountReadAt = previousReadAt }
            return false
        }
    }

    /// Profil personnel complet, relu auprès de l’école ; sa photo est relue si sa version a changé.
    private(set) var confirmedSelfProfile: SchoolSelfProfile?
    /// Photo confirmée en mémoire ; seuls les octets d’une intention encore à confirmer restent dans le journal chiffré.
    private(set) var selfPhoto: SchoolProfilePhoto?

    @discardableResult
    func loadSelfProfile() async throws -> SchoolSelfProfile {
        guard let current = confirmedPerson else { throw SchoolAPIError.unauthorized }
        let generation = accountRequest
        do {
            let profile = try await api.selfProfile()
            guard generation == accountRequest, profile.personId == current.personId, confirmedPerson?.personId == current.personId else { throw SchoolAPIError.invalidResponse }
            apply(profile)
            try restoreSelfIntents()
            await refreshSelfPhoto()
            guard generation == accountRequest, let latest = confirmedSelfProfile else { throw CancellationError() }
            return latest
        } catch {
            if generation == accountRequest { _ = invalidateAccess(for: error) }
            throw error
        }
    }

    /// L'intention est protégée avant d'être affichée ailleurs ou remise au transport.
    @discardableResult
    func retainSelfProfile(_ edit: SchoolSelfProfileEdit) throws -> UUID {
        try restoreSelfIntents()
        guard let base = confirmedSelfProfile else { throw SchoolAPIError.unavailable }
        let id = selfIntents.fields?.edit == edit ? selfIntents.fields?.id ?? UUID() : UUID()
        let intent = SchoolSelfProfileIntent(id: id, kind: .fields, base: base,
            fields: SchoolSelfProfileIntent.projecting(edit, on: base), jpeg: nil)
        var next = selfIntents; next.fields = intent
        try saveSelfIntents(next)
        return intent.id
    }

    @discardableResult
    func retainSelfPhoto(_ jpeg: Data?) throws -> UUID {
        try restoreSelfIntents()
        guard let current = confirmedPerson else { throw SchoolAPIError.unauthorized }
        guard jpeg.map({ $0.count <= 262_144 }) ?? true else { throw SchoolSelfProfileFailure.invalidPhoto }
        let base = confirmedSelfProfile ?? SchoolSelfProfile(personId: current.personId,
            displayName: current.displayName, version: current.version)
        let id = selfIntents.photo?.jpeg == jpeg ? selfIntents.photo?.id ?? UUID() : UUID()
        let intent = SchoolSelfProfileIntent(id: id, kind: .photo, base: base, fields: nil, jpeg: jpeg)
        var next = selfIntents; next.photo = intent
        try saveSelfIntents(next)
        return intent.id
    }

    func saveSelfProfile(_ edit: SchoolSelfProfileEdit) async throws {
        _ = try await sendSelfProfileIntent(retainSelfProfile(edit))
    }

    func setSelfPhoto(_ jpeg: Data?) async throws {
        _ = try await sendSelfProfileIntent(retainSelfPhoto(jpeg))
    }

    /// Une seule file par compte, même quand deux éditeurs ont été ouverts.
    /// `false` : un choix plus récent a remplacé celui-ci avant son départ.
    @discardableResult
    func sendSelfProfileIntent(_ id: UUID) async throws -> Bool {
        let generation = accountRequest
        let previous = selfWriteTail
        let work = Task { @MainActor [weak self] () async throws -> Bool in
            await previous?.value
            guard let self, self.accountRequest == generation else { throw CancellationError() }
            return try await self.sendRetainedSelfIntent(id, generation: generation)
        }
        selfWriteTail = Task { @MainActor in _ = try? await work.value }
        return try await work.value
    }

    private func restoreSelfIntents() throws {
        guard let current = confirmedPerson else { throw SchoolAPIError.unauthorized }
        guard let accountIntentBaseURL, let selfIntentStore else { return }
        let scope = AccountIntentScope(personID: current.personId, apiBaseURL: accountIntentBaseURL.absoluteString)
        guard selfIntentScope != scope else { return }
        do {
            let value = try selfIntentStore.read(scope: scope) ?? SchoolSelfProfileIntents()
            try value.validate(personID: current.personId)
            selfIntents = value; selfIntentScope = scope; selfProfileIntentError = nil
        } catch {
            selfProfileIntentError = "Les changements conservés sur cet appareil ne peuvent pas être lus. Réessaie après son déverrouillage."
            throw error
        }
    }

    private func saveSelfIntents(_ value: SchoolSelfProfileIntents) throws {
        do {
            if let selfIntentStore {
                guard let scope = selfIntentScope else { throw SchoolConfigurationFailure.storage }
                try selfIntentStore.save(value, scope: scope)
            }
            selfIntents = value; selfProfileIntentError = nil
        } catch {
            selfProfileIntentError = "La synchronisation ne peut pas être confirmée sur cet appareil. Tes changements restent à vérifier."
            throw error
        }
    }

    private func retainedSelfIntent(_ id: UUID) -> SchoolSelfProfileIntent? {
        [selfIntents.fields, selfIntents.photo].compactMap { $0 }.first { $0.id == id }
    }

    private func sendRetainedSelfIntent(_ id: UUID, generation: UUID) async throws -> Bool {
        guard retainedSelfIntent(id) != nil else { return false }
        do {
            if let attempted = selfIntents.attempted {
                // Une réponse perdue impose une lecture. Ne jamais transformer une nouvelle version en ACK.
                let remote = try await loadSelfProfile()
                guard generation == accountRequest else { throw CancellationError() }
                if try await matchesSelfIntent(attempted, profile: remote, generation: generation) {
                    try finishSelfIntent(attempted, profile: remote, photo: attempted.jpeg)
                } else if remote.version == attempted.base.version {
                    try await transmitSelfIntent(attempted, generation: generation)
                } else {
                    var next = selfIntents; next.attempted = nil
                    try saveSelfIntents(next)
                    throw SchoolSelfProfileFailure.changed
                }
                if attempted.id == id, retainedSelfIntent(id) == nil { return true }
            }
            guard var intent = retainedSelfIntent(id) else { return false }
            guard let current = confirmedPerson else { throw SchoolAPIError.unauthorized }
            var base = confirmedSelfProfile ?? intent.base
            // /me a pu observer une version plus récente que le profil complet.
            if current.version > base.version { base = try await loadSelfProfile() }
            guard generation == accountRequest else { throw CancellationError() }
            guard intent.baseStillMatches(base) else { throw SchoolSelfProfileFailure.changed }
            intent.base = base
            var next = selfIntents; next.attempted = intent
            try saveSelfIntents(next)
            try await transmitSelfIntent(intent, generation: generation)
            return true
        } catch {
            guard generation == accountRequest else { throw CancellationError() }
            if (error as? SchoolConfigurationFailure) != .storage {
                selfProfileIntentError = (error as? LocalizedError)?.errorDescription ?? SchoolAPIError.unavailable.localizedDescription
            }
            _ = invalidateAccess(for: error)
            throw error
        }
    }

    private func matchesSelfIntent(_ intent: SchoolSelfProfileIntent, profile: SchoolSelfProfile,
                                   generation: UUID) async throws -> Bool {
        switch intent.kind {
        case .fields: return intent.edit == SchoolSelfProfileEdit(profile)
        case .photo:
            guard let jpeg = intent.jpeg else { return profile.photoVersion == nil }
            guard profile.photoVersion != nil else { return false }
            let bytes = try await api.personPhoto(personID: profile.personId)
            // Le JPEG peut avoir été nettoyé par le serveur : une différence demande une revue, pas un faux ACK.
            let after = try await api.selfProfile()
            guard generation == accountRequest, after.personId == profile.personId else { throw CancellationError() }
            guard after.version == profile.version else { throw SchoolSelfProfileFailure.changed }
            return bytes == jpeg
        }
    }

    private func transmitSelfIntent(_ intent: SchoolSelfProfileIntent, generation: UUID) async throws {
        do {
            let profile: SchoolSelfProfile
            switch intent.kind {
            case .fields:
                guard let edit = intent.edit else { throw SchoolConfigurationFailure.storage }
                profile = try await api.saveSelfProfile(edit, version: intent.base.version)
            case .photo: profile = try await api.setSelfPhoto(intent.jpeg, version: intent.base.version)
            }
            guard generation == accountRequest else { throw CancellationError() }
            guard profile.personId == intent.base.personId, profile.version >= intent.base.version else {
                throw SchoolAPIError.invalidResponse
            }
            switch intent.kind {
            case .fields:
                guard intent.edit == SchoolSelfProfileEdit(profile) else { throw SchoolAPIError.invalidResponse }
            case .photo:
                guard (intent.jpeg == nil) == (profile.photoVersion == nil) else { throw SchoolAPIError.invalidResponse }
            }
            try finishSelfIntent(intent, profile: profile, photo: intent.jpeg)
        } catch let failure as SchoolSelfProfileFailure {
            guard generation == accountRequest else { throw CancellationError() }
            // Un refus explicite ne laisse pas une requête inconnue à rejouer. Le choix utile reste conservé.
            var next = selfIntents; next.attempted = nil
            try saveSelfIntents(next)
            if failure == .changed { _ = try? await loadSelfProfile() }
            throw failure
        }
    }

    private func finishSelfIntent(_ intent: SchoolSelfProfileIntent, profile: SchoolSelfProfile, photo: Data?) throws {
        apply(profile)
        if intent.kind == .photo, confirmedSelfProfile?.version == profile.version {
            selfPhoto = photo.flatMap { bytes in profile.photoVersion.map { SchoolProfilePhoto(version: $0, data: bytes) } }
            peoplePhotos.removeValue(forKey: profile.personId)
        }
        var next = selfIntents
        if next.fields?.id == intent.id { next.fields = nil }
        else if intent.kind == .fields { next.fields?.base = profile }
        if next.photo?.id == intent.id { next.photo = nil }
        else if intent.kind == .photo { next.photo?.base = profile }
        if next.attempted?.id == intent.id { next.attempted = nil }
        // Le résultat peut être acquis à l'école et son retrait local échouer : aucune confirmation locale mensongère.
        try saveSelfIntents(next)
    }

    /// Photos des autres personnes lues pendant la session (mémoire seulement). `nil` stocké : la personne n’en a pas.
    private(set) var peoplePhotos: [UUID: Data?] = [:]

    /// Photo d’une personne de l’école, lue une fois par session. Le compte connecté reprend la sienne.
    func photo(for personID: UUID) -> Data? {
        if personID == confirmedPerson?.personId {
            if let choice = pendingSelfPhotoChoice { return choice.jpeg }
            return selfPhoto?.data
        }
        return peoplePhotos[personID] ?? nil
    }

    /// Lectures de photo en cours : la liste et le dossier d’une même personne ne la demandent qu’une fois.
    @ObservationIgnored private var loadingPhotos: Set<UUID> = []

    func loadPhoto(for personID: UUID) async {
        guard personID != confirmedPerson?.personId, peoplePhotos[personID] == nil, !loadingPhotos.contains(personID) else { return }
        let scope = schoolScope
        loadingPhotos.insert(personID)
        defer { loadingPhotos.remove(personID) }
        do {
            let data = try await api.personPhoto(personID: personID)
            // Une réponse arrivée après un changement d’école n’est pas rangée dans la nouvelle portée.
            guard scope == schoolScope else { return }
            peoplePhotos[personID] = .some(data)
        } catch {
            // Une photo manquante n’est pas une erreur à montrer : les initiales restent.
        }
    }

    private func refreshSelfPhoto() async {
        guard let profile = confirmedSelfProfile else { return }
        guard let version = profile.photoVersion else { selfPhoto = nil; return }
        if selfPhoto?.version == version { return }
        selfPhoto = nil
        if let data = try? await api.personPhoto(personID: profile.personId), confirmedSelfProfile?.personId == profile.personId,
           confirmedSelfProfile?.photoVersion == version {
            selfPhoto = SchoolProfilePhoto(version: version, data: data)
        }
    }

    private func applyAccount(_ value: SchoolPerson) {
        // /me peut avoir commencé avant l'ACK d'une écriture. Ses droits restent frais, pas son ancien nom.
        if let profile = confirmedSelfProfile, profile.personId == value.personId, profile.version > value.version {
            confirmedPerson = SchoolPerson(personId: value.personId, version: profile.version,
                displayName: profile.displayName, locale: value.locale, memberships: value.memberships)
        } else { confirmedPerson = value }
    }

    private func apply(_ profile: SchoolSelfProfile) {
        guard let current = confirmedPerson, profile.personId == current.personId,
              profile.version >= (confirmedSelfProfile?.version ?? 0) else { return }
        confirmedSelfProfile = profile
        if profile.version >= current.version, current.displayName != profile.displayName || current.version != profile.version {
            confirmedPerson = SchoolPerson(personId: current.personId, version: profile.version, displayName: profile.displayName,
                locale: current.locale, memberships: current.memberships)
        }
    }

    /// Le portail peut activer l'école sans changer les rôles : son retour relit aussi l'état scolaire.
    func willOpenManagement() { awaitsManagementReturn = true }

    func refreshOnForeground() async {
        if awaitsManagementReturn || school?.status == "DRAFT" {
            await refreshEntry()
        } else {
            await refreshAccount()
            await refreshLearners()
            if entryDestination == .instructor { await refreshOwnLearner() }
        }
    }

    /// Relecture explicite de l'entrée, sans effacer l'état confirmé en cas de panne.
    func refreshEntry() async {
        guard confirmedPerson != nil, !isLoadingAccount, !isLoadingSchool, !isRefreshingEntry else { return }
        isRefreshingEntry = true
        defer { isRefreshingEntry = false }
        let request = accountRequest, previousScope = schoolScope
        guard await refreshAccount(minimumInterval: 0) else {
            if request == accountRequest, !accessRevoked { schoolError = "Les accès de l’école n’ont pas pu être vérifiés. Réessayez." }
            return
        }
        guard request == accountRequest, !accessRevoked, let selected = membership else { return }
        // Un changement de rôle ou d'école a déjà déclenché selectSchool pendant la relecture des droits.
        if previousScope == schoolScope { await selectSchool(selected) }
        if request == accountRequest, schoolError == nil, school?.id == membership?.schoolId {
            awaitsManagementReturn = false
        }
    }

    func selectSchool(_ selected: SchoolMembership) async {
        guard confirmedPerson?.memberships.contains(selected) == true else { return }
        var resumesLearner = false
        if membership == selected {
            // Même école, mêmes droits (nouvel essai, retour d'une adhésion) : la portée reste en place pour que les
            // écrans ouverts ne se ferment pas. Les réponses en vol de l'ancienne lecture sont écartées par le nouveau scope.
            schoolScope = UUID()
            schoolError = nil
            isLoadingSchool = false
            // Une lecture du dossier écartée ici ne rend jamais la main : ses indicateurs repartent de zéro et le
            // dossier est relu une fois l'école confirmée, au lieu de rester sur un chargement sans fin.
            resumesLearner = selectedLearnerID != nil
                && (isLoadingLearner || isLoadingTrainings || isLoadingMoreTrainings || (confirmedLearner == nil && learnerError == nil))
            isLoadingLearner = false; isLoadingTrainings = false; isLoadingMoreTrainings = false
            // Même règle pour la liste : une recherche ou une page écartée ne laisse pas son attente affichée.
            isSearching = false; isLoadingMoreLearners = false
        } else {
            clearSchool()
            membership = selected
        }
        let scope = schoolScope
        isLoadingSchool = true
        do {
            let result = try await api.school(id: selected.schoolId)
            guard scope == schoolScope else { return }
            guard result.id == selected.schoolId else { throw SchoolAPIError.invalidResponse }
            school = result
            isLoadingSchool = false
            if result.status == "ACTIVE" {
                await searchLearners("")
                if scope == schoolScope, entryDestination == .instructor { await refreshOwnLearner(minimumInterval: 0) }
                await refreshLearnersToComplete()
            } else {
                confirmedOwnLearner = nil; ownLearnerError = nil; ownLearnerReadAt = nil
            }
            if resumesLearner, scope == schoolScope, selectedLearnerID != nil, !isLoadingLearner {
                await loadSelectedLearner()
            }
        } catch {
            guard scope == schoolScope else { return }
            isLoadingSchool = false
            if !invalidateAccess(for: error) { schoolError = blockingMessage(for: error) }
        }
    }

    func leaveSchool() { clearSchool() }

    func rejectCurrentAccess(requiresAuthentication: Bool) {
        invalidateAccess(for: requiresAuthentication ? SchoolAPIError.unauthorized : SchoolAPIError.forbidden)
    }

    /// Called by the search field. Purge happens at keystroke time, before the
    /// debounce delay or any transport cancellation can complete.
    func setSearchText(_ text: String) {
        beginSearch(text)
        guard let schoolID = membership?.schoolId else { return }
        let scope = schoolScope
        let request = searchRequest
        let query = normalizedQuery
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.fetchLearners(schoolID: schoolID, query: query, scope: scope, request: request)
        }
    }

    /// Le filtre « Profil à compléter » relit la liste depuis la première page, recherche en cours comprise.
    func setIncompleteProfilesOnly(_ value: Bool) async {
        guard value != showsIncompleteProfilesOnly else { return }
        showsIncompleteProfilesOnly = value
        await searchLearners(searchText)
    }

    /// Une page de la liste de l’équipe, filtre compris.
    private func staffLearnersPage(schoolID: UUID, query: String, cursor: String?) async throws -> SchoolPage<SchoolLearner> {
        if showsIncompleteProfilesOnly { return try await api.incompleteLearners(schoolID: schoolID, query: query, cursor: cursor) }
        return try await api.learners(schoolID: schoolID, query: query, cursor: cursor)
    }

    /// Immediate equivalent used for explicit retry and deterministic tests.
    func searchLearners(_ text: String) async {
        let sameQuery = text.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedQuery
        beginSearch(text, preservingSelection: sameQuery)
        guard let schoolID = membership?.schoolId else { return }
        await fetchLearners(schoolID: schoolID, query: normalizedQuery, scope: schoolScope, request: searchRequest)
    }

    /// Retour dans l’app ou sur l’onglet Élèves : la première page de la recherche en cours est relue sans rien
    /// effacer, au plus une fois par minute. Un élève qui vient de rejoindre l’école apparaît, une ligne modifiée
    /// suit, la sélection, le dossier ouvert et les pages déjà chargées restent. Une panne ne dit rien : la liste
    /// affichée reste lisible et la prochaine occasion réessaie.
    func refreshLearners(minimumInterval: TimeInterval = 60, now: Date = Date()) async {
        guard let schoolID = membership?.schoolId, school?.status == "ACTIVE", learnersError == nil,
              !isLoadingSchool, !isSearching, !isLoadingMoreLearners else { return }
        if let learnersReadAt, now.timeIntervalSince(learnersReadAt) < minimumInterval { return }
        let scope = schoolScope
        let request = searchRequest
        let query = normalizedQuery
        let previousReadAt = learnersReadAt
        learnersReadAt = now
        do {
            let page: SchoolPage<SchoolLearner>
            if entryDestination == .learner && query.isEmpty { page = try await api.ownLearners(schoolID: schoolID) }
            else { page = try await staffLearnersPage(schoolID: schoolID, query: query, cursor: nil) }
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            if entryDestination == .learner && query.isEmpty {
                confirmedOwnLearner = page.items.first { $0.personId == confirmedPerson?.personId }
            }
            var fresh: [SchoolLearner] = []
            Self.merge(page.items, into: &fresh)
            noteProfiles(page.items)
            if learnerCursors.isEmpty {
                // Une seule page affichée : elle est remplacée par sa relecture.
                confirmedLearners = fresh
                nextLearnersCursor = page.nextCursor
            } else {
                // Des pages suivantes sont affichées : la première est relue, les lignes des autres restent à leur suite.
                let read = Set(fresh.map(\.id))
                confirmedLearners = fresh + confirmedLearners.filter { !read.contains($0.id) }
            }
        } catch {
            guard scope == schoolScope, request == searchRequest else { return }
            if !invalidateAccess(for: error) { learnersReadAt = previousReadAt }
        }
    }

    /// Un compte moniteur et élève garde son dossier même s’il est absent de la page de l’annuaire.
    /// La réponse relue reste limitée à ce compte, cette école et les droits courants.
    func refreshOwnLearner(minimumInterval: TimeInterval = 60, now: Date = Date()) async {
        guard let membership, membership.roles.contains("LEARNER"), let personID = confirmedPerson?.personId,
              school?.status == "ACTIVE" else { return }
        if let ownLearnerReadAt, now.timeIntervalSince(ownLearnerReadAt) < minimumInterval { return }
        let scope = schoolScope, previousReadAt = ownLearnerReadAt
        ownLearnerRequest = UUID()
        let request = ownLearnerRequest
        ownLearnerReadAt = now; ownLearnerError = nil
        do {
            let page = try await api.ownLearners(schoolID: membership.schoolId)
            guard scope == schoolScope, request == ownLearnerRequest else { return }
            guard page.nextCursor == nil, page.items.count <= 1,
                  page.items.allSatisfy({ $0.schoolId == membership.schoolId && $0.personId == personID }) else {
                throw SchoolAPIError.invalidResponse
            }
            confirmedOwnLearner = page.items.first
        } catch {
            guard scope == schoolScope, request == ownLearnerRequest else { return }
            if !invalidateAccess(for: error) {
                ownLearnerReadAt = previousReadAt
                ownLearnerError = message(for: error)
            }
        }
    }

    /// Relit les dossiers à compléter de toute l’école (administration seulement). Une panne garde ce qui a été lu :
    /// elle n’allume ni n’éteint aucun point ; un refus d’accès ferme la portée comme ailleurs.
    func refreshLearnersToComplete() async {
        guard let schoolID = membership?.schoolId, membership?.roles.contains("ADMIN") == true, school?.status == "ACTIVE" else { return }
        let scope = schoolScope
        do {
            guard let items = try await api.learnersToComplete(schoolID: schoolID), scope == schoolScope else { return }
            guard items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            let read = Set(items.filter(SchoolRequiredActionRules.profileIsIncomplete).map(\.id))
            if read != learnersToComplete { learnersToComplete = read }
        } catch {
            guard scope == schoolScope else { return }
            invalidateAccess(for: error)
        }
    }

    /// Un élève relu ici (dossier, liste) corrige aussitôt l’ensemble des dossiers à compléter : une correction
    /// enregistrée éteint son point sans attendre la prochaine lecture de l’école.
    private func noteProfiles(_ items: [SchoolLearner]) {
        if membership?.roles.contains("LEARNER") == true,
           let own = items.first(where: { $0.personId == confirmedPerson?.personId && $0.schoolId == membership?.schoolId }) {
            confirmedOwnLearner = own
        }
        guard var pending = learnersToComplete else { return }
        for item in items {
            if SchoolRequiredActionRules.profileIsIncomplete(item) { pending.insert(item.id) } else { pending.remove(item.id) }
        }
        if pending != learnersToComplete { learnersToComplete = pending }
    }

    func loadMoreLearners() async {
        guard !isSearching, !isLoadingMoreLearners,
              let schoolID = membership?.schoolId, let cursor = nextLearnersCursor else { return }
        let scope = schoolScope
        let request = searchRequest
        let query = normalizedQuery
        isLoadingMoreLearners = true
        learnersError = nil
        do {
            let page = try await staffLearnersPage(schoolID: schoolID, query: query, cursor: cursor)
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            guard page.nextCursor != cursor,
                  page.nextCursor.map({ !learnerCursors.contains($0) }) ?? true else { throw SchoolAPIError.invalidCursor }
            learnerCursors.insert(cursor)
            Self.merge(page.items, into: &confirmedLearners)
            noteProfiles(page.items)
            nextLearnersCursor = page.nextCursor
            isLoadingMoreLearners = false
        } catch {
            guard scope == schoolScope, request == searchRequest else { return }
            isLoadingMoreLearners = false
            if !invalidateAccess(for: error) { learnersError = message(for: error) }
        }
    }

    /// Nom d’un élève hors de la page affichée (trajet en cours) ; une lecture refusée ou en panne ne dit rien.
    func learnerName(_ id: UUID) async -> String? {
        guard let schoolID = membership?.schoolId else { return nil }
        let scope = schoolScope
        guard let value = try? await api.learner(schoolID: schoolID, id: id), scope == schoolScope,
              value.schoolId == schoolID, value.id == id else { return nil }
        return projectedLearner(value).displayName
    }

    func selectLearner(_ id: UUID?) {
        guard selectedLearnerID != id else { return }
        clearLearner()
        selectedLearnerID = id
    }

    func loadSelectedLearner() async {
        guard let schoolID = membership?.schoolId, let id = selectedLearnerID else { return }
        let scope = schoolScope
        learnerRequest = UUID()
        let request = learnerRequest
        trainingsRequest = UUID()
        isLoadingTrainings = false
        isLoadingMoreTrainings = false
        learnerError = nil
        // Relecture du dossier déjà affiché : il reste à l’écran jusqu’à la réponse, sans écran de chargement.
        isLoadingLearner = confirmedLearner?.id != id
        do {
            let result = try await api.learner(schoolID: schoolID, id: id)
            guard scope == schoolScope, request == learnerRequest, selectedLearnerID == id else { return }
            guard result.id == id, result.schoolId == schoolID else { throw SchoolAPIError.invalidResponse }
            confirmedLearner = result
            // La liste Élèves porte le même élève : sa ligne suit le dossier relu (nom, coordonnées) sans attendre sa
            // propre relecture. Ni l’ordre ni la pagination ne changent, et un élève absent de la liste n’y est pas ajouté.
            if let row = confirmedLearners.firstIndex(where: { $0.id == result.id }) { confirmedLearners[row] = result }
            noteProfiles([result])
            isLoadingLearner = false
            await loadTrainings()
        } catch {
            guard scope == schoolScope, request == learnerRequest else { return }
            isLoadingLearner = false
            if error as? SchoolAPIError == .notFound {
                clearLearner()
                selectedLearnerID = id
            }
            if !invalidateAccess(for: error) { learnerError = message(for: error) }
        }
    }

    func loadTrainings() async {
        guard let schoolID = membership?.schoolId, let learnerID = selectedLearnerID, confirmedLearner != nil else { return }
        let scope = schoolScope
        let request = learnerRequest
        trainingsRequest = UUID()
        let pageRequest = trainingsRequest
        // Refreshing the list must not close a formation already open in the dossier, nor remove the
        // screen (and the sheets it carries) that depends on it: the rows already read stay until the
        // answer replaces them. They always belong to this learner (changing learner clears them).
        // Its independent detail request remains bound to its selection and schoolScope.
        trainingsError = nil
        isLoadingMoreTrainings = false
        isLoadingTrainings = true
        do {
            let page = try await api.trainings(schoolID: schoolID, learnerID: learnerID, cursor: nil)
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            var fresh: [SchoolTraining] = []
            Self.merge(page.items, into: &fresh)
            trainings = fresh
            trainingCursors = []
            nextTrainingsCursor = page.nextCursor
            isLoadingTrainings = false
        } catch {
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            isLoadingTrainings = false
            if !invalidateAccess(for: error) { trainingsError = message(for: error) }
        }
    }

    func loadMoreTrainings() async {
        guard !isLoadingTrainings, !isLoadingMoreTrainings,
              let schoolID = membership?.schoolId, let learnerID = selectedLearnerID,
              let cursor = nextTrainingsCursor else { return }
        let scope = schoolScope
        let request = learnerRequest
        let pageRequest = trainingsRequest
        isLoadingMoreTrainings = true
        trainingsError = nil
        do {
            let page = try await api.trainings(schoolID: schoolID, learnerID: learnerID, cursor: cursor)
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID && $0.learnerId == learnerID }) else { throw SchoolAPIError.invalidResponse }
            guard page.nextCursor != cursor,
                  page.nextCursor.map({ !trainingCursors.contains($0) }) ?? true else { throw SchoolAPIError.invalidCursor }
            trainingCursors.insert(cursor)
            Self.merge(page.items, into: &trainings)
            nextTrainingsCursor = page.nextCursor
            isLoadingMoreTrainings = false
        } catch {
            guard scope == schoolScope, request == learnerRequest, pageRequest == trainingsRequest else { return }
            isLoadingMoreTrainings = false
            if !invalidateAccess(for: error) { trainingsError = message(for: error) }
        }
    }

    /// Les filtres par permis portent sur toutes les formations de l’élève, pas sur la première page.
    /// Une panne laisse le curseur en place : le dossier propose alors de continuer.
    func loadRemainingTrainings() async {
        while let cursor = nextTrainingsCursor, !isLoadingTrainings, !isLoadingMoreTrainings {
            await loadMoreTrainings()
            if nextTrainingsCursor == cursor || trainingsError != nil { return }
        }
    }

    private var normalizedQuery: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func beginSearch(_ text: String, preservingSelection: Bool = false) {
        debounceTask?.cancel()
        debounceTask = nil
        searchRequest = UUID()
        searchText = text
        if !preservingSelection { confirmedLearners = [] }
        nextLearnersCursor = nil
        learnerCursors = []
        learnersError = nil
        isSearching = membership != nil
        isLoadingMoreLearners = false
        if !preservingSelection { clearLearner() }
    }

    private func fetchLearners(schoolID: UUID, query: String, scope: UUID, request: UUID) async {
        guard scope == schoolScope, request == searchRequest else { return }
        do {
            // L’élève cherche son seul dossier, archivé compris ; l’équipe garde la liste des dossiers actifs.
            let page: SchoolPage<SchoolLearner>
            if entryDestination == .learner && query.isEmpty { page = try await api.ownLearners(schoolID: schoolID) }
            else { page = try await staffLearnersPage(schoolID: schoolID, query: query, cursor: nil) }
            guard scope == schoolScope, request == searchRequest else { return }
            guard page.items.allSatisfy({ $0.schoolId == schoolID }) else { throw SchoolAPIError.invalidResponse }
            if entryDestination == .learner && query.isEmpty {
                confirmedOwnLearner = page.items.first { $0.personId == confirmedPerson?.personId }
            }
            confirmedLearners = []
            Self.merge(page.items, into: &confirmedLearners)
            noteProfiles(page.items)
            nextLearnersCursor = page.nextCursor
            isSearching = false
            learnersReadAt = Date()
        } catch {
            guard scope == schoolScope, request == searchRequest else { return }
            isSearching = false
            if !invalidateAccess(for: error) { learnersError = message(for: error) }
        }
    }

    private func clearSchool() {
        schoolScope = UUID()
        membership = nil
        school = nil
        // Les photos et le filtre appartiennent à l’école quittée : rien n’en reparaît dans la suivante.
        peoplePhotos = [:]
        showsIncompleteProfilesOnly = false
        schoolError = nil
        isLoadingSchool = false
        learnersReadAt = nil
        ownLearnerRequest = UUID(); confirmedOwnLearner = nil; ownLearnerError = nil; ownLearnerReadAt = nil
        learnersToComplete = nil
        beginSearch("")
    }

    private func clearLearner() {
        learnerRequest = UUID()
        trainingsRequest = UUID()
        selectedLearnerID = nil
        confirmedLearner = nil
        learnerError = nil
        isLoadingLearner = false
        trainings = []
        nextTrainingsCursor = nil
        trainingCursors = []
        trainingsError = nil
        isLoadingTrainings = false
        isLoadingMoreTrainings = false
    }

    @discardableResult
    private func invalidateAccess(for error: any Error) -> Bool {
        guard let failure = error as? SchoolAPIError else { return false }
        switch failure {
        case .unauthorized, .forbidden, .identityNotLinked:
            reset()
            requiresAuthentication = failure == .unauthorized
            identityNotLinked = failure == .identityNotLinked
            accessRevoked = true
            accountError = message(for: failure)
            return true
        default:
            return false
        }
    }

    /// Le message d’une panne. Une lecture annulée (écran fermé, relecture qui la remplace, geste d’actualisation
    /// interrompu) n’en est pas une : `nil`, ce qui est affiché reste et la prochaine lecture reprend. Seuls le compte
    /// et l’école, sans quoi rien ne s’affiche, disent l’interruption pour proposer de réessayer.
    private func message(for error: any Error) -> String? {
        if error.isRequestCancellation { return nil }
        return (error as? SchoolAPIError)?.localizedDescription ?? "La connexion a échoué. Tes données n’ont pas été modifiées."
    }
    private func blockingMessage(for error: any Error) -> String {
        message(for: error) ?? "Le chargement a été interrompu. Réessaie."
    }

    private static func merge<T: Identifiable>(_ newItems: [T], into items: inout [T]) where T.ID: Hashable {
        var indices = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        for item in newItems {
            if let index = indices[item.id] { items[index] = item }
            else { indices[item.id] = items.count; items.append(item) }
        }
    }
}
