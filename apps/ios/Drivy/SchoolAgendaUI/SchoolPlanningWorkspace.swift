import Foundation
import Observation

/// Lecture lancée à part pour partir en même temps que d’autres : l’annulation de celui qui l’attend l’annule aussi.
extension Task where Failure == any Error {
    var readValue: Success {
        get async throws {
            try await withTaskCancellationHandler { try await value } onCancel: { cancel() }
        }
    }
}

struct SchoolPlanningInstructor: Identifiable {
    let id: UUID
    let displayName: String
}

/// Valeurs saisies, distinctes du chargement, de la disponibilité et de la demande déjà conservée dans la file.
struct SchoolPlanningDraftSnapshot: Equatable {
    let learnerID: UUID?, trainingID: UUID?, instructorID: UUID?, productID: UUID?
    let startsAt: Date
    let duration: Int
    let meetingPoint: String
    let bufferMinutes: Int
    let quantity: Int
    let agreementConfirmed: Bool
    let changesCommercialTerms: Bool
    let reason: String
    let cancellationReason: String
}

@MainActor @Observable final class SchoolPlanningWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolPlanningClient
    private(set) var originalLesson: SchoolLesson?
    /// Feuille « Annuler la leçon » : la lecture se limite à l’école et à la leçon. Fixé par la feuille avant sa lecture.
    var readsForCancellation = false
    /// A durable command receipt closes the live capture even if the following read fails.
    private(set) var confirmedCancellationLessonID: UUID?
    /// Leçon relue après le reçu durable d'une création ou d'un déplacement. Jamais remplie par une demande incertaine.
    private(set) var confirmedLesson: SchoolLesson?
    private(set) var roles: [String] = []
    private(set) var grants: [String] = []
    private(set) var school: SchoolDetails?
    private(set) var defaults: SchoolPlanningDefaults?
    private(set) var learners: [SchoolLearner] = []
    private(set) var trainings: [SchoolTraining] = []
    private(set) var offerings: [SchoolOffering] = []
    private(set) var policies: [SchoolCatalogPolicy] = []
    private(set) var products: [SchoolServiceProduct] = []
    private(set) var terms: [SchoolCommercialTerms] = []
    private(set) var instructors: [SchoolPlanningInstructor] = []
    private(set) var assignments: [SchoolAssignment] = []
    private(set) var availability: [SchoolAvailabilityRule] = []
    private(set) var closures: [SchoolClosure] = []
    private(set) var isLoadingAvailability = false
    private(set) var availabilityLoaded = false
    private(set) var availabilityError: String?
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var needsReload = true
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var pendingRequiresReview = false
    /// Demande que l’école a déclaré ne pas connaître : elle peut être renvoyée comme neuve, ou abandonnée.
    private(set) var absentPendingID: UUID?
    var pendingAbsent: Bool { pending != nil && pending?.id == absentPendingID }
    private(set) var accessRevoked = false
    private(set) var isCheckingSlot = false
    private(set) var slotError: String?
    private(set) var slotAvailability: SchoolPlanningSlotAvailability?
    /// Le dernier créneau vérifié était libre : pendant la vérification d’un horaire retouché, le formulaire garde
    /// ses sections et sa barre au lieu de les retirer puis de les remettre.
    private(set) var lastSlotWasAvailable = false
    /// L’école a confirmé l’écriture : la feuille se ferme sur ce résultat. Rien ne change à l’écran pendant sa
    /// descente ; seul un second envoi est empêché, jusqu’à une nouvelle lecture.
    private(set) var writeConfirmed = false
    private(set) var checkedSlotRequest: SchoolPlanningSlotRequest?
    private(set) var selectedDurationMinutes: Int?
    /// « Planifier une leçon » propose le prochain créneau libre au lieu d’une heure arbitraire. Un déplacement garde
    /// l’horaire de la leçon et ne cherche jamais.
    let suggestsNextSlot: Bool
    private(set) var suggestedSlot: SchoolSuggestedSlotState = .idle
    /// Recherche à laquelle répond `suggestedSlot` : un autre moniteur, une autre durée ou une recherche élargie en relancent une.
    private(set) var suggestedSlotRequest: SchoolPlanningNextSlotRequest?
    /// Le moniteur a choisi lui-même la date ou l’heure : plus aucune proposition ne remplace son choix.
    private(set) var startChosenByUser = false
    /// Recherche élargie : reprise au jour civil qui suit la dernière période examinée.
    private(set) var suggestionResumesAt: Date?
    @ObservationIgnored private let searchStart: Date
    @ObservationIgnored private var suggestionGeneration = UUID()
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var selectionGeneration = UUID()
    @ObservationIgnored private var availabilityGeneration = UUID()
    @ObservationIgnored private var slotGeneration = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAvailable = false
    @ObservationIgnored private var confirmedLessonReference: (id: UUID, version: Int)?
    var learnerID: UUID?
    var trainingID: UUID?
    var instructorID: UUID? {
        didSet {
            if instructorID != oldValue {
                availabilityGeneration = UUID()
                clearAvailability()
            }
        }
    }
    var productID: UUID? {
        didSet {
            if productID != oldValue {
                agreementConfirmed = false
                if let minutes = selectedProduct?.durationMinutes, minutes > 0, duration % minutes == 0 {
                    quantity = duration / minutes
                }
            }
        }
    }
    var startsAt: Date {
        didSet { if startsAt != oldValue { refreshProductSelection(); agreementConfirmed = false } }
    }
    var meetingPoint = ""
    var bufferMinutes = 10
    var quantity = 1 {
        didSet {
            if quantity != oldValue {
                agreementConfirmed = false
                if let minutes = selectedProduct?.durationMinutes, (1...100).contains(quantity) {
                    selectedDurationMinutes = minutes * quantity
                }
            }
        }
    }
    var agreementConfirmed = false
    var changesCommercialTerms = false {
        didSet { if changesCommercialTerms != oldValue { agreementConfirmed = false } }
    }
    var reason = ""
    var cancellationReason = ""
    var draftSnapshot: SchoolPlanningDraftSnapshot {
        SchoolPlanningDraftSnapshot(learnerID: learnerID, trainingID: trainingID, instructorID: instructorID, productID: productID,
            startsAt: startsAt, duration: duration, meetingPoint: meetingPoint, bufferMinutes: bufferMinutes, quantity: quantity,
            agreementConfirmed: agreementConfirmed, changesCommercialTerms: changesCommercialTerms, reason: reason,
            cancellationReason: cancellationReason)
    }

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, date: Date = Date(), lesson: SchoolLesson? = nil,
         suggestingNextSlotFrom: Date? = nil, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; originalLesson = lesson; self.outbox = outbox
        // `date` reste l’horaire initial si l’école ne connaît pas la recherche ; celle-ci part de `suggestingNextSlotFrom`.
        suggestsNextSlot = suggestingNextSlotFrom != nil && lesson == nil; searchStart = suggestingNextSlotFrom ?? date
        startsAt = lesson?.startsAt ?? Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60)
        if let lesson {
            learnerID = lesson.learnerId; trainingID = lesson.trainingId; instructorID = lesson.instructorMembershipId
            meetingPoint = lesson.meetingPoint; bufferMinutes = lesson.bufferMinutesSnapshot
        }
    }
    var canMutate: Bool { !invalidated && !accessRevoked && !isBusy && !isLoading && !needsReload && !writeConfirmed && storageAvailable && pending == nil && school?.status == "ACTIVE" }
    var selectedTraining: SchoolTraining? { trainings.first { $0.id == trainingID } }
    var selectedOffering: SchoolOffering? { offerings.first { $0.id == selectedTraining?.offeringId } }
    var selectedProduct: SchoolServiceProduct? { products.first { $0.id == productID } }
    var selectedTerms: SchoolCommercialTerms? { terms.first { $0.id == selectedProduct?.termsVersionId } }
    var selectedPolicy: SchoolCatalogPolicy? { policies.first { $0.id == selectedOffering?.policyVersionId } }
    var timeZone: String { school?.timeZone ?? originalLesson?.timeZone ?? "Europe/Zurich" }
    /// The instructor's name, followed by a short reference when another instructor has the same one.
    func instructorLabel(_ instructor: SchoolPlanningInstructor) -> String {
        HomonymReference.label(instructor.displayName,
                               reference: HomonymReference.references(instructors.map { ($0.id, $0.displayName) })[instructor.id])
    }
    var assignedInstructors: [SchoolPlanningInstructor] {
        let now = Date()
        let ids = Set(assignments.filter { assignment in
            guard let from = SchoolLesson.date(assignment.validFrom), from <= now, from <= startsAt else { return false }
            if let value = assignment.validUntil {
                guard let until = SchoolLesson.date(value), until > now, until >= endsAt else { return false }
            }
            return true
        }.map(\.instructorMembershipId))
        return instructors.filter { ids.contains($0.id) }
    }
    var availableProducts: [SchoolServiceProduct] {
        let date = SchoolCatalogFormatting.civilDate(startsAt, timeZone: timeZone)
        return products.filter { $0.enabled && $0.current != false && $0.siteId == nil && $0.type == "INDIVIDUAL_LESSON" && $0.categoryCode == selectedTraining?.categoryCode
            && ($0.durationMinutes ?? 0) > 0 && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) }
    }
    var selectedPrice: Int64? {
        guard let product = selectedProduct, (1...100).contains(quantity) else { return nil }
        let result = product.unitPriceCents.multipliedReportingOverflow(by: Int64(quantity))
        return result.overflow || result.partialValue > 9_007_199_254_740_991 ? nil : result.partialValue
    }
    var duration: Int {
        if let originalLesson, !changesCommercialTerms { return originalLesson.durationMinutes }
        if let selectedDurationMinutes { return selectedDurationMinutes }
        guard let minutes = selectedOffering?.defaultDurationMinutes, (1...480).contains(minutes) else { return 0 }
        return minutes
    }
    /// Duration remains editable before choosing a price, including after an unavailable slot.
    var durationChoices: [Int] {
        var values = Set<Int>()
        if (1...480).contains(duration) { values.insert(duration) }
        if let minutes = selectedOffering?.defaultDurationMinutes, (1...480).contains(minutes) { values.insert(minutes) }
        for product in availableProducts {
            guard let minutes = product.durationMinutes, (1...480).contains(minutes) else { continue }
            for quantity in 1...min(100, 480 / minutes) { values.insert(minutes * quantity) }
        }
        return values.sorted()
    }
    var compatibleProducts: [SchoolServiceProduct] {
        let date = SchoolCatalogFormatting.civilDate(startsAt, timeZone: timeZone)
        return availableProducts.filter { product in
            guard let minutes = product.durationMinutes, minutes > 0 else { return false }
            return duration > 0 && duration % minutes == 0 && (1...100).contains(duration / minutes)
                && terms.contains { $0.id == product.termsVersionId && $0.approved && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) }
        }
    }
    /// Quantité de cette prestation que couvre la durée choisie (1 si la durée n’en est pas un multiple).
    func quantityCovered(by product: SchoolServiceProduct) -> Int {
        guard let minutes = product.durationMinutes, minutes > 0, duration > 0, duration % minutes == 0 else { return 1 }
        return max(1, duration / minutes)
    }
    /// Le seul tarif possible, déjà retenu : il n’y a rien à choisir, le formulaire l’indique sans sélecteur.
    var automaticTariff: SchoolServiceProduct? {
        let products = compatibleProducts
        guard products.count == 1, let product = products.first, product.id == productID else { return nil }
        return product
    }
    /// Plusieurs tarifs possibles, ou un seul que le formulaire n’a pas retenu : le choix revient au moniteur.
    var needsTariffChoice: Bool { !compatibleProducts.isEmpty && automaticTariff == nil }
    /// Ce qui empêche de retenir un tarif quand le formulaire en attend un.
    /// Nil si un tarif est retenu, ou s’il n’est pas en jeu (déplacement qui garde la durée et le prix).
    var tariffMessage: String? {
        guard trainingID != nil, !isLoading, originalLesson == nil || changesCommercialTerms else { return nil }
        let products = compatibleProducts
        if products.contains(where: { $0.id == productID }) { return nil }
        return products.isEmpty ? "Aucun tarif ne correspond à cette durée et à cette date." : "Choisis un tarif."
    }
    func selectDuration(_ minutes: Int) {
        guard (1...480).contains(minutes) else { return }
        selectedDurationMinutes = minutes; agreementConfirmed = false
        refreshProductSelection()
    }
    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(duration * 60)) }
    var slotInputMessage: String? {
        guard trainingID != nil, !isLoading, !awaitingSuggestedSlot else { return nil }
        if startsAt <= Date() { return "Choisis un horaire à venir." }
        if !(1...480).contains(duration) { return "Choisis une durée de 1 à 480 minutes." }
        if !(0...240).contains(bufferMinutes) { return "Choisis un intervalle entre les leçons de 0 à 240 minutes." }
        if let instructorID, !assignedInstructors.contains(where: { $0.id == instructorID }) {
            return "L’affectation du moniteur doit couvrir toute la leçon. Choisis un autre horaire ou moniteur."
        }
        return nil
    }
    var slotRequest: SchoolPlanningSlotRequest? {
        guard !invalidated, !accessRevoked, !isLoading, !needsReload, school?.status == "ACTIVE", !awaitingSuggestedSlot,
              let learnerID, learners.contains(where: { $0.id == learnerID }), let training = selectedTraining,
              training.learnerId == learnerID, let instructorID,
              assignedInstructors.contains(where: { $0.id == instructorID }), slotInputMessage == nil else { return nil }
        return SchoolPlanningSlotRequest(learnerID: learnerID, trainingID: training.id, instructorID: instructorID,
            startsAt: startsAt, endsAt: endsAt, timeZone: timeZone, bufferMinutes: bufferMinutes, excludedLessonID: originalLesson?.id)
    }
    var slotIsAvailable: Bool {
        slotRequest != nil && checkedSlotRequest == slotRequest && !isCheckingSlot && slotAvailability?.available == true
    }
    var slotValidationRequest: SchoolPlanningSlotRequest? { canMutate ? slotRequest : nil }
    /// Sections du créneau (motif, accord, documents) et barre d’action : visibles quand le créneau est libre, et
    /// pendant la vérification d’un horaire retouché après un créneau libre. Seul le bouton attend la réponse.
    var showsSlotDetails: Bool {
        guard slotRequest != nil, slotInputMessage == nil else { return false }
        return slotIsAvailable || (lastSlotWasAvailable && slotError == nil && slotAvailability?.available != false)
    }
    /// The API trims the value then applies JavaScript's 500 UTF-16 code-unit limit.
    var meetingPointTooLong: Bool { meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 500 }
    var reasonTooLong: Bool { reason.utf16.count > 1000 }
    var validBooking: Bool {
        guard canMutate, !writeConfirmed, slotIsAvailable, let training = selectedTraining, training.learnerId == learnerID,
              learners.contains(where: { $0.id == learnerID }), let instructorID, assignedInstructors.contains(where: { $0.id == instructorID }),
              !meetingPointTooLong, (1...480).contains(duration), (0...240).contains(bufferMinutes), startsAt > Date() else { return false }
        if let originalLesson {
            guard originalLesson.status == "PLANNED", agreementConfirmed, !reasonTooLong else { return false }
            if !changesCommercialTerms { return true }
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        let date = SchoolCatalogFormatting.civilDate(startsAt, timeZone: timeZone)
        return selectedOffering?.enabled == true && selectedPolicy?.approved == true && selectedPrice != nil
            && selectedTerms?.approved == true && compatibleProducts.contains { $0.id == productID }
            && selectedProduct.map { ($0.durationMinutes ?? 0) * quantity == duration } == true
            && selectedTerms.map { $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) } == true
    }
    func invalidate() {
        invalidated = true; generation = UUID(); selectionGeneration = UUID(); availabilityGeneration = UUID(); clear()
    }
    private func clear() {
        school = nil; defaults = nil; learners = []; trainings = []; offerings = []; policies = []; products = []; terms = []
        instructors = []; assignments = []; clearAvailability(); clearSlot(); clearSuggestion(); pending = nil
        storageAvailable = false; needsReload = true; isBusy = false; isLoading = false
        confirmedLesson = nil; confirmedLessonReference = nil
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        let previousInstructorID = instructorID
        generation = UUID(); selectionGeneration = UUID(); availabilityGeneration = UUID(); let request = generation
        clearSlot()
        // Keep this instructor's last confirmed data while the same scope is reread.
        // A changed instructor or revoked access still clears it immediately.
        isLoadingAvailability = false; availabilityError = nil
        isLoading = true; needsReload = true; errorMessage = nil; storageAvailable = false; writeConfirmed = false
        confirmedLesson = nil; confirmedLessonReference = nil
        defer { if request == generation { isLoading = false } }
        var storageError: String?
        do { pending = try outbox.pending(for: scope, domain: .teaching); storageAvailable = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let person = try await client.reader.me()
            guard let membership = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
                  person.personId == scope.personID, membership.schoolId == scope.schoolID, membership.accessEpoch == scope.accessEpoch,
                  membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { throw SchoolPlanningFailure.forbidden }
            // Les droits du compte sont relus d’abord ; les lectures suivantes sont indépendantes et partent ensemble.
            // Rien n’est publié avant la fin de toutes : l’ordre des réponses ne change pas ce qui est affiché.
            let isAdmin = membership.roles.contains("ADMIN")
            let schoolRead = Task<SchoolDetails, any Error> { @MainActor in try await self.client.reader.school(id: self.scope.schoolID) }
            let lessonRead = Task<SchoolLesson?, any Error> { @MainActor in try await self.readOriginalLesson() }
            defer { schoolRead.cancel(); lessonRead.cancel() }
            if readsForCancellation {
                // Annuler une leçon ne demande que l’école et la leçon : ni catalogue, ni élèves.
                let school = try await schoolRead.readValue
                let refreshedLesson = try await lessonRead.readValue
                guard request == generation, !Task.isCancelled else { return }
                self.school = school; self.roles = membership.roles; self.grants = membership.grants
                originalLesson = refreshedLesson; agreementConfirmed = false
                needsReload = false; isLoading = false; errorMessage = storageError
                return
            }
            let defaultsRead = Task<SchoolPlanningDefaults, any Error> { @MainActor in
                try await self.client.defaults(schoolID: self.scope.schoolID, membershipID: self.scope.membershipID)
            }
            let offeringsRead = Task<[SchoolOffering], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["offerings"]) }
            let policiesRead = Task<[SchoolCatalogPolicy], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["policy-versions"]) }
            let productsRead = Task<[SchoolServiceProduct], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["service-products"]) }
            let termsRead = Task<[SchoolCommercialTerms], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["commercial-terms"]) }
            let membersRead = Task<[SchoolMember], any Error> { @MainActor in try await self.readMembers(isAdmin: isAdmin) }
            let learnersRead = Task<[SchoolLearner], any Error> { @MainActor in try await self.readAllLearners() }
            defer {
                defaultsRead.cancel(); offeringsRead.cancel(); policiesRead.cancel(); productsRead.cancel()
                termsRead.cancel(); membersRead.cancel(); learnersRead.cancel()
            }
            let school = try await schoolRead.readValue
            let defaults = try await defaultsRead.readValue
            let refreshedLesson = try await lessonRead.readValue
            let offerings = try await offeringsRead.readValue
            let policies = try await policiesRead.readValue
            let products = try await productsRead.readValue
            let terms = try await termsRead.readValue
            guard products.allSatisfy({ (0...9_007_199_254_740_991).contains($0.unitPriceCents)
                && ($0.durationMinutes.map { (1...1440).contains($0) } ?? true) }) else { throw SchoolPlanningFailure.invalidResponse }
            let instructors: [SchoolPlanningInstructor]
            if isAdmin {
                let members = try await membersRead.readValue
                instructors = members.filter { $0.status == "ACTIVE" && $0.roles.contains("INSTRUCTOR") }.map { SchoolPlanningInstructor(id: $0.id, displayName: $0.displayName) }
            } else { instructors = [SchoolPlanningInstructor(id: membership.membershipId, displayName: person.displayName)] }
            let learners = try await learnersRead.readValue
            guard request == generation, !Task.isCancelled else { return }
            self.school = school; self.defaults = defaults; self.roles = membership.roles; self.grants = membership.grants
            self.offerings = offerings; self.policies = policies; self.products = products; self.terms = terms
            self.instructors = instructors
            self.learners = learners.filter { $0.archivedAt == nil }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            originalLesson = refreshedLesson; agreementConfirmed = false
            needsReload = false; isLoading = false; errorMessage = storageError
            if let learnerID, self.learners.contains(where: { $0.id == learnerID }) { await selectLearner(learnerID) }
            else {
                learnerID = nil; trainingID = nil; trainings = []; assignments = []; instructorID = nil; productID = nil
            }
            // The retained form's task(id:) does not restart when the instructor stays the same.
            if request == generation, instructorID != nil, instructorID == previousInstructorID {
                await loadAvailability()
            }
        } catch {
            // Feuille refermée pendant la lecture : une interruption n’est ni un refus ni une panne à afficher.
            guard request == generation, !(error is CancellationError) else { return }
            fail(error)
        }
    }
    private func readOriginalLesson() async throws -> SchoolLesson? {
        guard let originalLesson else { return nil }
        return try await client.lesson(schoolID: scope.schoolID, id: originalLesson.id)
    }
    /// L’équipe ne se lit que pour l’administration ; un moniteur ne planifie que pour lui-même.
    private func readMembers(isAdmin: Bool) async throws -> [SchoolMember] {
        guard isAdmin else { return [] }
        return try await client.records(scope.schoolID, path: ["members"])
    }
    private func readAllLearners() async throws -> [SchoolLearner] {
        var learners: [SchoolLearner] = [], cursor: String?, seen = Set<String>()
        repeat {
            let page = try await client.reader.learners(schoolID: scope.schoolID, query: "", cursor: cursor)
            learners.append(contentsOf: page.items); cursor = page.nextCursor
            guard learners.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
            if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
        } while cursor != nil
        return learners
    }
    func selectLearner(_ id: UUID) async {
        guard !invalidated, !isBusy else { return }
        selectionGeneration = UUID(); let request = selectionGeneration
        guard learners.contains(where: { $0.id == id }) else { return }
        let keepsSelection = learnerID == id
        let previousTrainingID = keepsSelection ? trainingID : nil
        let previousProductID = keepsSelection ? productID : nil
        learnerID = id; assignments = []; productID = nil
        if !keepsSelection { trainings = []; instructorID = nil; selectedDurationMinutes = nil; suggestionResumesAt = nil }
        if originalLesson == nil { trainingID = nil }
        isLoading = true
        do {
            let trainings: [SchoolTraining] = try await client.records(scope.schoolID, path: ["trainings"], query: [URLQueryItem(name: "learnerId", value: id.uuidString)])
            guard request == selectionGeneration, !invalidated, !Task.isCancelled else { return }
            self.trainings = trainings.filter { $0.learnerId == id && ($0.status == "ACTIVE" || $0.id == originalLesson?.trainingId) }
            isLoading = false
            if originalLesson == nil {
                trainingID = self.trainings.contains(where: { $0.id == previousTrainingID }) ? previousTrainingID : defaults?.trainingID(in: self.trainings)
            }
            if let trainingID {
                if trainingID == previousTrainingID { productID = previousProductID }
                await selectTraining(trainingID)
            }
        } catch { guard request == selectionGeneration else { return }; isLoading = false; fail(error) }
    }
    func selectTraining(_ id: UUID) async {
        guard !invalidated, !isBusy else { return }
        guard trainings.contains(where: { $0.id == id }) else { return }
        selectionGeneration = UUID(); let request = selectionGeneration
        let previousInstructorID = trainingID == id ? instructorID : nil
        if trainingID != id { productID = nil; selectedDurationMinutes = nil }
        trainingID = id; assignments = []; isLoading = true
        do {
            let records: [SchoolAssignment] = try await client.records(scope.schoolID, path: ["trainings", id.uuidString, "assignments"])
            guard request == selectionGeneration, !invalidated, !Task.isCancelled else { return }
            assignments = records; isLoading = false
            if selectedDurationMinutes == nil {
                let date = SchoolCatalogFormatting.civilDate(startsAt, timeZone: timeZone)
                let valid = availableProducts.filter { product in
                    (1...480).contains(product.durationMinutes ?? 0) && terms.contains {
                        $0.id == product.termsVersionId && $0.approved && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true)
                    }
                }
                let preferred = valid.filter { $0.productKey == defaults?.serviceProductKey }
                let initial = preferred.count == 1 ? preferred.first : valid.count == 1 ? valid.first : nil
                selectedDurationMinutes = initial?.durationMinutes
            }
            refreshProductSelection()
            if originalLesson == nil {
                if let previousInstructorID, assignedInstructors.contains(where: { $0.id == previousInstructorID }) {
                    instructorID = previousInstructorID
                } else {
                    instructorID = assignedInstructors.contains(where: { $0.id == scope.membershipID }) ? scope.membershipID
                        : assignedInstructors.count == 1 ? assignedInstructors.first?.id : nil
                }
            }
        } catch { guard request == selectionGeneration else { return }; isLoading = false; fail(error) }
    }
    private func refreshProductSelection() {
        let valid = compatibleProducts
        if let product = valid.first(where: { $0.id == productID }), let minutes = product.durationMinutes {
            quantity = duration / minutes; return
        }
        let preferred = valid.filter { $0.productKey == defaults?.serviceProductKey }
        productID = preferred.count == 1 ? preferred.first?.id : valid.count == 1 ? valid.first?.id : nil
    }
    /// This read is advisory; the write still atomically rechecks the reservation on the server.
    func validateSlot(debounced: Bool = false) async {
        slotGeneration = UUID(); let requestGeneration = slotGeneration
        slotAvailability = nil; slotError = nil; checkedSlotRequest = nil; isCheckingSlot = false
        guard canMutate, let slot = slotRequest else { return }
        checkedSlotRequest = slot; isCheckingSlot = true
        defer { if requestGeneration == slotGeneration { isCheckingSlot = false } }
        do {
            if debounced { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            let result = try await client.availability(schoolID: scope.schoolID, slot: slot)
            guard requestGeneration == slotGeneration, slot == slotRequest, !Task.isCancelled else { return }
            slotAvailability = result; lastSlotWasAvailable = result.available
        } catch {
            guard requestGeneration == slotGeneration, slot == slotRequest, !Task.isCancelled else { return }
            lastSlotWasAvailable = false
            if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized {
                fail(error)
            } else {
                slotError = (error as? LocalizedError)?.errorDescription ?? "La disponibilité n’a pas pu être vérifiée. Réessaie."
            }
        }
    }
    private func clearSlot() {
        slotGeneration = UUID(); checkedSlotRequest = nil; slotAvailability = nil; slotError = nil; isCheckingSlot = false
        lastSlotWasAvailable = false
    }
    // MARK: Prochain créneau libre

    /// Ce que la recherche demande au serveur ; nil tant qu’il manque l’élève, la formation, le moniteur ou la durée,
    /// ou dès que le moniteur a choisi son horaire.
    var nextSlotRequest: SchoolPlanningNextSlotRequest? {
        guard suggestsNextSlot, !startChosenByUser, canMutate, let learnerID, learners.contains(where: { $0.id == learnerID }),
              let training = selectedTraining, training.learnerId == learnerID,
              let instructorID, instructors.contains(where: { $0.id == instructorID }),
              (1...480).contains(duration), (0...240).contains(bufferMinutes) else { return nil }
        return SchoolPlanningNextSlotRequest(learnerID: learnerID, trainingID: training.id, instructorID: instructorID,
            durationMinutes: duration, bufferMinutes: bufferMinutes, timeZone: timeZone, from: suggestionResumesAt ?? searchStart)
    }
    /// La date et l’heure ne s’affichent qu’une fois la proposition calculée : jamais une date provisoire qui saute ensuite.
    var awaitingSuggestedSlot: Bool {
        guard suggestsNextSlot, !startChosenByUser, trainingID != nil else { return false }
        if let request = nextSlotRequest { return suggestedSlotRequest != request || suggestedSlot == .searching }
        // Affectations en lecture : le moniteur n’est pas encore connu. Seule la toute première recherche attend ainsi.
        return isLoading && suggestedSlotRequest == nil
    }
    /// Message de la recherche courante : rien quand un créneau est trouvé, que la recherche tourne ou que le moniteur a choisi.
    var suggestedSlotNotice: SchoolSuggestedSlotState? {
        guard let request = nextSlotRequest, request == suggestedSlotRequest else { return nil }
        switch suggestedSlot {
        case .exhausted, .failed: return suggestedSlot
        default: return nil
        }
    }
    /// Choix manuel de la date ou de l’heure : il l’emporte sur toute proposition, même en cours.
    func chooseStart(_ date: Date) {
        if suggestsNextSlot && !startChosenByUser {
            startChosenByUser = true; suggestionGeneration = UUID()
            if suggestedSlot == .searching { suggestedSlot = .idle; suggestedSlotRequest = nil }
        }
        startsAt = date
    }
    /// « Choisir moi-même » pendant la recherche (#149) : la date et l’heure s’ouvrent aussitôt sur l’horaire en place ;
    /// une proposition arrivée ensuite ne remplace plus rien. « Planifier » revérifie toujours le créneau.
    func chooseStartManually() { chooseStart(startsAt) }
    /// Aucun créneau dans la période : la recherche reprend au jour qui suit la dernière date examinée.
    func searchFurther() {
        guard case .exhausted(let through) = suggestedSlot, suggestedSlotNotice != nil,
              let next = SchoolPlanningNextSlot.startOfNextCivilDay(after: through, zone: timeZone) else { return }
        suggestionResumesAt = next
    }
    /// Lecture indicative : « Planifier » revérifie le créneau, puis l’école le contrôle de nouveau à l’écriture.
    func findSuggestedSlot(retrying: Bool = false) async {
        guard let request = nextSlotRequest else { return }
        if !retrying, suggestedSlotRequest == request, suggestedSlot != .idle { return }
        suggestionGeneration = UUID(); let generation = suggestionGeneration
        suggestedSlotRequest = request; suggestedSlot = .searching
        do {
            let result = try await client.nextSlot(schoolID: scope.schoolID, request: request)
            guard generation == suggestionGeneration, request == nextSlotRequest, !Task.isCancelled else {
                if generation == suggestionGeneration { suggestedSlot = .idle; suggestedSlotRequest = nil }
                return
            }
            if let start = result.startsAt {
                startsAt = start; suggestedSlot = .found
            } else {
                suggestedSlot = .exhausted(searchedThrough: result.searchedThrough)
            }
        } catch {
            guard generation == suggestionGeneration else { return }
            if error is CancellationError || Task.isCancelled { suggestedSlot = .idle; suggestedSlotRequest = nil; return }
            if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized {
                suggestedSlot = .idle; fail(error)
            } else if error as? SchoolPlanningFailure == .notFound {
                // Service antérieur à la recherche : le formulaire reste celui d’avant, l’horaire se choisit à la main.
                suggestedSlot = .unavailable
            } else {
                suggestedSlot = .failed((error as? LocalizedError)?.errorDescription ?? "Le prochain créneau n’a pas pu être cherché.")
            }
        }
    }
    private func clearSuggestion() {
        suggestionGeneration = UUID(); suggestedSlot = .idle; suggestedSlotRequest = nil
    }

    func loadAvailability() async {
        guard let instructorID, !invalidated, !accessRevoked else { clearAvailability(); return }
        let request = generation; availabilityGeneration = UUID(); let availabilityRequest = availabilityGeneration
        availabilityError = nil; isLoadingAvailability = true
        defer {
            if request == generation, availabilityRequest == availabilityGeneration { isLoadingAvailability = false }
        }
        do {
            let query = [URLQueryItem(name: "instructorMembershipId", value: instructorID.uuidString)]
            let rules: [SchoolAvailabilityRule] = try await client.records(scope.schoolID, path: ["availability-rules"], query: query)
            guard request == generation, availabilityRequest == availabilityGeneration, self.instructorID == instructorID,
                  !invalidated, !accessRevoked, !Task.isCancelled else { return }
            let closures: [SchoolClosure] = try await client.records(scope.schoolID, path: ["closures"], query: query)
            guard request == generation, availabilityRequest == availabilityGeneration, self.instructorID == instructorID,
                  !invalidated, !accessRevoked, !Task.isCancelled else { return }
            guard rules.allSatisfy({ $0.instructorMembershipId == instructorID }),
                  closures.allSatisfy({ $0.instructorMembershipId == instructorID }) else { throw SchoolPlanningFailure.invalidResponse }
            availability = rules; self.closures = closures; availabilityLoaded = true
        } catch {
            guard request == generation, availabilityRequest == availabilityGeneration, self.instructorID == instructorID,
                  !invalidated, !accessRevoked, !Task.isCancelled else { return }
            if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized
                || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
                fail(error)
            } else {
                availabilityError = (error as? LocalizedError)?.errorDescription ?? "Les disponibilités n’ont pas pu être chargées."
            }
        }
    }
    private func clearAvailability() {
        availability = []; closures = []; isLoadingAvailability = false; availabilityLoaded = false; availabilityError = nil
    }
    func saveBooking() async -> Bool {
        guard validBooking, let instructorID, let trainingID else { return false }
        // « Planifier » confirme le prix affiché et les versions alors sélectionnées.
        // Aucun accord n’est enregistré pendant la simple consultation du formulaire.
        let iso = ISO8601DateFormatter()
        var body: [String: Any] = ["plannedStart": iso.string(from: startsAt), "plannedEnd": iso.string(from: endsAt),
            "timeZone": timeZone, "meetingPoint": meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines), "instructorMembershipId": instructorID.uuidString]
        if let lesson = originalLesson {
            body["agreementConfirmed"] = true; body["reason"] = reason
            if changesCommercialTerms {
                guard let selection = commercialSelection, let price = selectedPrice else { return false }
                body["commercialChange"] = ["commercialSelection": selection, "agreedPriceCents": price,
                    "expectedAccountVersion": NSNull(), "reason": reason.trimmingCharacters(in: .whitespacesAndNewlines)] as [String: Any]
            }
            return await submit(.moveLesson, body: body, resourceID: lesson.id, version: lesson.version)
        }
        guard let selection = commercialSelection, let policy = selectedPolicy, let price = selectedPrice else { return false }
        body["trainingId"] = trainingID.uuidString; body["policyVersionId"] = policy.id.uuidString
        body["agreedPriceCents"] = price; body["bufferMinutes"] = bufferMinutes
        body["commercialSelection"] = selection
        return await submit(.createLesson, body: body, routeID: trainingID)
    }
    func cancel() async -> Bool {
        guard !writeConfirmed, let lesson = originalLesson, lesson.status == "PLANNED", !reasonTooLong,
              ["LEARNER_REQUEST", "INSTRUCTOR_UNAVAILABLE", "SCHOOL_CLOSURE", "OTHER"].contains(cancellationReason) else { return false }
        return await submit(.cancelLesson, body: ["reasonCode": cancellationReason, "comment": reason], resourceID: lesson.id, version: lesson.version)
    }
    private var commercialSelection: [String: Any]? {
        guard let product = selectedProduct else { return nil }
        return ["mode": "UNIT_PRICE", "serviceProductVersionId": product.id.uuidString, "quantity": quantity,
            "entitlementLotId": NSNull(), "acceptedTermsVersionId": product.termsVersionId.uuidString]
    }
    func submit(_ kind: SchoolCommandKind, body: [String: Any], resourceID: UUID? = nil, version: Int = 0, routeID: UUID? = nil) async -> Bool {
        guard canMutate, kind.isPlanning else { return false }
        do {
            let id = UUID(); var body = body; body["operationId"] = id.uuidString
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            guard data.count <= 200_000 else { throw SchoolPlanningFailure.rejected("Ce contenu est trop volumineux.") }
            let command = PendingSchoolCommand(id: id, scope: scope, kind: kind, resourceVersion: version,
                createdAt: Date(), body: data, resourceID: resourceID, routeResourceID: routeID)
            pending = command; pendingRequiresReview = false
            do { try outbox.save(command) }
            catch {
                storageAvailable = false
                if let existing = try? outbox.pending(for: scope, domain: .teaching) { pending = existing }
                throw error
            }
        } catch { fail(error); return false }
        return await transmit(firstAttempt: true)
    }
    var canRetry: Bool { !invalidated && !isBusy && !isLoading && !accessRevoked && !pendingRequiresReview && pending?.scope == scope && pending?.kind.isPlanning == true }
    func retry() async -> Bool { await transmit(firstAttempt: false) }
    func verify() async {
        guard !invalidated, !isBusy, let command = pending, command.scope.belongsToWorkspace(scope) else { return }
        isBusy = true; let request = generation
        do {
            let receipt = try await client.receipt(for: command); try outbox.remove(command)
            guard request == generation else { return }
            pending = nil; isBusy = false; pendingRequiresReview = false
            if command.kind == .cancelLesson {
                confirmedCancellationLessonID = command.resourceID; writeConfirmed = true
            }
            if command.kind == .createLesson || command.kind == .moveLesson {
                writeConfirmed = true
                confirmedLessonReference = (receipt.resourceId, receipt.resourceVersion)
                await reloadConfirmedLesson()
                // Changement de compte ou accès retiré pendant la relecture : rien n'est annoncé dans l'ancienne portée.
                guard request == generation, !invalidated, !accessRevoked else { return }
                successMessage = "Enregistrement confirmé par l’école."
                NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
                return
            }
            if command.kind != .cancelLesson { await load() }
            successMessage = "Enregistrement confirmé par l’école."
            NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
        } catch SchoolPlanningFailure.notFound {
            // Le reçu absent ne dit rien des accès : l’école n’a simplement pas enregistré cette opération.
            guard request == generation else { return }
            isBusy = false; errorMessage = nil; absentPendingID = command.id; pendingRequiresReview = false
        } catch { guard request == generation else { return }; isBusy = false; fail(error) }
    }
    /// Retire une demande que l’école ne connaît pas, puis relit le planning : rien n’est supposé enregistré.
    func abandonPending() async {
        guard !invalidated, !isBusy, let command = pending, pendingAbsent else { return }
        do { try outbox.remove(command) }
        catch { storageAvailable = false; fail(error); return }
        pending = nil; absentPendingID = nil; errorMessage = nil
        await load()
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation; isBusy = true; errorMessage = nil; successMessage = nil
        do {
            try outbox.save(command)
            let receipt = try await client.send(command)
            // Création et déplacement ouvrent la fiche relue : sans reçu AP72, l'écriture reste à vérifier, jamais refusée.
            // « Lancer maintenant » confirme par sa propre réponse et ne doit jamais rester bloqué dans le coffre.
            if (command.kind == .createLesson || command.kind == .moveLesson) && receipt == nil {
                throw SchoolPlanningFailure.unavailable
            }
            try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; isBusy = false; successMessage = "Enregistrement confirmé par l’école."
            if command.kind == .cancelLesson { confirmedCancellationLessonID = command.resourceID }
            // La feuille se ferme sur ce résultat : relire tout le planning derrière elle ne faisait que retarder sa
            // fermeture et changer le formulaire sous les yeux. Une nouvelle saisie exigerait une relecture.
            writeConfirmed = true
            NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
            if command.kind == .createLesson || command.kind == .moveLesson, let receipt {
                confirmedLessonReference = (receipt.resourceId, receipt.resourceVersion)
                return await reloadConfirmedLesson()
            }
            return true
        } catch {
            guard request == generation else { return false }
            if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection || failure == .notFound {
                // Une demande que l’école ne connaît pas se renvoie comme neuve : son refus est alors définitif.
                // Un 404 est aussi une réponse de l’école : rien n’a été enregistré.
                if firstAttempt || command.id == absentPendingID {
                    do { try outbox.remove(command); pending = nil; absentPendingID = nil; needsReload = true }
                    catch { storageAvailable = false; isBusy = false; fail(error); return false }
                } else { pendingRequiresReview = true }
            }
            isBusy = false; fail(error); return false
        }
    }

    /// Relit la ressource désignée par le reçu. Une panne ici ne rend pas l'écriture incertaine et ne renvoie jamais
    /// la commande : l'utilisateur peut seulement reprendre la lecture de la fiche confirmée.
    @discardableResult func reloadConfirmedLesson() async -> Bool {
        guard !invalidated, let reference = confirmedLessonReference else { return false }
        let request = generation
        isBusy = true; errorMessage = nil
        defer { if request == generation { isBusy = false } }
        do {
            let lesson = try await client.lesson(schoolID: scope.schoolID, id: reference.id)
            guard request == generation, !invalidated, !accessRevoked, confirmedLessonReference?.id == reference.id,
                  confirmedLessonReference?.version == reference.version else { return false }
            guard lesson.version >= reference.version else { throw SchoolPlanningFailure.invalidResponse }
            confirmedLesson = lesson
            return true
        } catch {
            guard request == generation, !invalidated else { return false }
            confirmedLesson = nil
            if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized
                || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
                fail(error)
            } else {
                errorMessage = "La leçon est enregistrée, mais sa fiche n’a pas pu être chargée. Réessaie."
            }
            return false
        }
    }
    private func fail(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le planning n’a pas pu être mis à jour."
        if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized
            || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
            clear(); accessRevoked = true
        }
    }
}

/// État de la proposition du prochain créneau libre.
enum SchoolSuggestedSlotState: Equatable {
    case idle, searching, found
    /// Aucun créneau libre jusqu’à ce jour civil inclus.
    case exhausted(searchedThrough: String)
    case failed(String)
    /// L’école ne propose pas encore cette recherche : saisie manuelle.
    case unavailable
}
