import Foundation
import Observation

struct SchoolPlanningInstructor: Identifiable {
    let id: UUID
    let displayName: String
}

@MainActor @Observable final class SchoolPlanningWorkspace: Identifiable {
    let id = UUID()
    let scope: SchoolCommandScope
    let client: SchoolPlanningClient
    private(set) var originalLesson: SchoolLesson?
    /// A durable command receipt closes the live capture even if the following read fails.
    private(set) var confirmedCancellationLessonID: UUID?
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
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var selectionGeneration = UUID()
    @ObservationIgnored private var availabilityGeneration = UUID()
    @ObservationIgnored private var slotGeneration = UUID()
    @ObservationIgnored private var invalidated = false
    @ObservationIgnored private var storageAvailable = false
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

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, date: Date = Date(), lesson: SchoolLesson? = nil,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; originalLesson = lesson; self.outbox = outbox
        startsAt = lesson?.startsAt ?? Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60)
        if let lesson {
            learnerID = lesson.learnerId; trainingID = lesson.trainingId; instructorID = lesson.instructorMembershipId
            meetingPoint = lesson.meetingPoint; bufferMinutes = lesson.bufferMinutesSnapshot
        }
    }
    var canMutate: Bool { !invalidated && !accessRevoked && !isBusy && !isLoading && !needsReload && storageAvailable && pending == nil && school?.status == "ACTIVE" }
    var selectedTraining: SchoolTraining? { trainings.first { $0.id == trainingID } }
    var selectedOffering: SchoolOffering? { offerings.first { $0.id == selectedTraining?.offeringId } }
    var selectedProduct: SchoolServiceProduct? { products.first { $0.id == productID } }
    var selectedTerms: SchoolCommercialTerms? { terms.first { $0.id == selectedProduct?.termsVersionId } }
    var selectedPolicy: SchoolCatalogPolicy? { policies.first { $0.id == selectedOffering?.policyVersionId } }
    var timeZone: String { school?.timeZone ?? originalLesson?.timeZone ?? "Europe/Zurich" }
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
        guard trainingID != nil, !isLoading else { return nil }
        if startsAt <= Date() { return "Choisis un horaire à venir." }
        if !(1...480).contains(duration) { return "Choisis une durée de 1 à 480 minutes." }
        if !(0...240).contains(bufferMinutes) { return "Choisis un intervalle entre les leçons de 0 à 240 minutes." }
        if let instructorID, !assignedInstructors.contains(where: { $0.id == instructorID }) {
            return "L’affectation du moniteur doit couvrir toute la leçon. Choisis un autre horaire ou moniteur."
        }
        return nil
    }
    var slotRequest: SchoolPlanningSlotRequest? {
        guard !invalidated, !accessRevoked, !isLoading, !needsReload, school?.status == "ACTIVE",
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
        instructors = []; assignments = []; clearAvailability(); clearSlot(); pending = nil
        storageAvailable = false; needsReload = true; isBusy = false; isLoading = false
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
        defer { if request == generation { isLoading = false } }
        var storageError: String?
        do { pending = try outbox.pending(for: scope); storageAvailable = true }
        catch { storageError = SchoolConfigurationFailure.storage.localizedDescription }
        do {
            let person = try await client.reader.me()
            guard let membership = person.memberships.first(where: { $0.membershipId == scope.membershipID }),
                  person.personId == scope.personID, membership.schoolId == scope.schoolID, membership.accessEpoch == scope.accessEpoch,
                  membership.roles.contains("ADMIN") || membership.roles.contains("INSTRUCTOR") else { throw SchoolPlanningFailure.forbidden }
            let school = try await client.reader.school(id: scope.schoolID)
            let defaults = try await client.defaults(schoolID: scope.schoolID, membershipID: scope.membershipID)
            let refreshedLesson: SchoolLesson?
            if let originalLesson { refreshedLesson = try await client.lesson(schoolID: scope.schoolID, id: originalLesson.id) }
            else { refreshedLesson = nil }
            let offerings: [SchoolOffering] = try await client.records(scope.schoolID, path: ["offerings"])
            let policies: [SchoolCatalogPolicy] = try await client.records(scope.schoolID, path: ["policy-versions"])
            let products: [SchoolServiceProduct] = try await client.records(scope.schoolID, path: ["service-products"])
            let terms: [SchoolCommercialTerms] = try await client.records(scope.schoolID, path: ["commercial-terms"])
            guard products.allSatisfy({ (0...9_007_199_254_740_991).contains($0.unitPriceCents)
                && ($0.durationMinutes.map { (1...1440).contains($0) } ?? true) }) else { throw SchoolPlanningFailure.invalidResponse }
            var instructors: [SchoolPlanningInstructor]
            if membership.roles.contains("ADMIN") {
                let members: [SchoolMember] = try await client.records(scope.schoolID, path: ["members"])
                instructors = members.filter { $0.status == "ACTIVE" && $0.roles.contains("INSTRUCTOR") }.map { SchoolPlanningInstructor(id: $0.id, displayName: $0.displayName) }
            } else { instructors = [SchoolPlanningInstructor(id: membership.membershipId, displayName: person.displayName)] }
            var learners: [SchoolLearner] = [], cursor: String?, seen = Set<String>()
            repeat {
                let page = try await client.reader.learners(schoolID: scope.schoolID, query: "", cursor: cursor)
                learners.append(contentsOf: page.items); cursor = page.nextCursor
                guard learners.count <= 10_000 else { throw SchoolPlanningFailure.invalidResponse }
                if let cursor, !seen.insert(cursor).inserted { throw SchoolPlanningFailure.invalidResponse }
            } while cursor != nil
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
        } catch { if request == generation { fail(error) } }
    }
    func selectLearner(_ id: UUID) async {
        guard !invalidated, !isBusy else { return }
        selectionGeneration = UUID(); let request = selectionGeneration
        guard learners.contains(where: { $0.id == id }) else { return }
        let keepsSelection = learnerID == id
        let previousTrainingID = keepsSelection ? trainingID : nil
        let previousProductID = keepsSelection ? productID : nil
        learnerID = id; assignments = []; productID = nil
        if !keepsSelection { trainings = []; instructorID = nil; selectedDurationMinutes = nil }
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
                if let existing = try? outbox.pending(for: scope) { pending = existing }
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
            _ = try await client.receipt(for: command); try outbox.remove(command)
            guard request == generation else { return }; pending = nil; isBusy = false; pendingRequiresReview = false
            if command.kind == .cancelLesson { confirmedCancellationLessonID = command.resourceID }
            successMessage = "Enregistrement confirmé par l’école."
            NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
            await load()
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
            try outbox.save(command); try await client.send(command); try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; isBusy = false; successMessage = "Enregistrement confirmé par l’école."
            if command.kind == .cancelLesson { confirmedCancellationLessonID = command.resourceID }
            // La feuille se ferme sur ce résultat : relire tout le planning derrière elle ne faisait que retarder sa
            // fermeture et changer le formulaire sous les yeux. Une nouvelle saisie exigerait une relecture.
            writeConfirmed = true
            NotificationCenter.default.post(name: .drivyLessonsDidChange, object: nil)
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
    private func fail(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? "Le planning n’a pas pu être mis à jour."
        if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized
            || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
            clear(); accessRevoked = true
        }
    }
}
