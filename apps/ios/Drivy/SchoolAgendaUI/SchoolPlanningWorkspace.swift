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
    private(set) var roles: [String] = [], grants: [String] = []
    private(set) var school: SchoolDetails?
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
    private(set) var pending: PendingSchoolCommand?
    private(set) var isLoading = false, isBusy = false, needsReload = true
    private(set) var errorMessage: String?, successMessage: String?
    private(set) var pendingRequiresReview = false
    private(set) var accessRevoked = false
    @ObservationIgnored private let outbox: any SchoolCommandOutbox
    @ObservationIgnored private var generation = UUID(), selectionGeneration = UUID(), availabilityGeneration = UUID()
    @ObservationIgnored private var invalidated = false, storageAvailable = false
    var learnerID: UUID?, trainingID: UUID?, instructorID: UUID?, productID: UUID?
    var startsAt: Date
    var meetingPoint = "", bufferMinutes = 10, quantity = 1
    var termsAccepted = false, agreementConfirmed = false
    var changesCommercialTerms = false
    var reason = "", cancellationReason = ""

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, date: Date = Date(), lesson: SchoolLesson? = nil,
         outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; originalLesson = lesson; self.outbox = outbox
        startsAt = lesson?.startsAt ?? Date(timeIntervalSince1970: ceil(date.timeIntervalSince1970 / 60) * 60)
        if let lesson {
            learnerID = lesson.learnerId; trainingID = lesson.trainingId; instructorID = lesson.instructorMembershipId
            meetingPoint = lesson.meetingPoint; bufferMinutes = lesson.bufferMinutesSnapshot
        }
    }
    var canConfigureCatalog: Bool { roles.contains("ADMIN") && grants.contains("CONFIGURE_CATALOG") }
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
        return products.filter { $0.enabled && $0.siteId == nil && $0.type == "INDIVIDUAL_LESSON" && $0.categoryCode == selectedTraining?.categoryCode
            && ($0.durationMinutes ?? 0) > 0 && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) }
    }
    var selectedPrice: Int64? {
        guard let product = selectedProduct, (1...100).contains(quantity) else { return nil }
        let result = product.unitPriceCents.multipliedReportingOverflow(by: Int64(quantity))
        return result.overflow || result.partialValue > 9_007_199_254_740_991 ? nil : result.partialValue
    }
    var duration: Int {
        if let originalLesson, !changesCommercialTerms { return originalLesson.durationMinutes }
        return (selectedProduct?.durationMinutes ?? 0) * quantity
    }
    var endsAt: Date { startsAt.addingTimeInterval(TimeInterval(duration * 60)) }
    var validBooking: Bool {
        guard canMutate, trainingID != nil, let instructorID, assignedInstructors.contains(where: { $0.id == instructorID }), !meetingPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              meetingPoint.count <= 500, (1...480).contains(duration), (0...240).contains(bufferMinutes), startsAt > Date() else { return false }
        if let originalLesson {
            guard originalLesson.status == "PLANNED", agreementConfirmed, reason.count <= 1000 else { return false }
            if !changesCommercialTerms { return true }
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        }
        let date = SchoolCatalogFormatting.civilDate(startsAt, timeZone: timeZone)
        return selectedOffering?.enabled == true && selectedPolicy?.approved == true && selectedPrice != nil && termsAccepted
            && selectedTerms?.approved == true && availableProducts.contains { $0.id == productID }
            && selectedTerms.map { $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) } == true
    }
    func invalidate() {
        invalidated = true; generation = UUID(); selectionGeneration = UUID(); availabilityGeneration = UUID(); clear()
    }
    private func clear() {
        school = nil; learners = []; trainings = []; offerings = []; policies = []; products = []; terms = []
        instructors = []; assignments = []; availability = []; closures = []; pending = nil
        storageAvailable = false; needsReload = true; isBusy = false; isLoading = false
    }
    func load() async {
        guard !invalidated, !isBusy else { return }
        generation = UUID(); selectionGeneration = UUID(); availabilityGeneration = UUID(); let request = generation
        isLoading = true; needsReload = true; errorMessage = nil; storageAvailable = false
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
            self.school = school; self.roles = membership.roles; self.grants = membership.grants
            self.offerings = offerings; self.policies = policies; self.products = products; self.terms = terms
            self.instructors = instructors; self.learners = learners.filter { $0.archivedAt == nil }
            originalLesson = refreshedLesson; agreementConfirmed = false
            needsReload = false; isLoading = false; errorMessage = storageError
            if let learnerID { await selectLearner(learnerID) }
        } catch { if request == generation { fail(error) } }
    }
    func selectLearner(_ id: UUID) async {
        guard !invalidated, !isBusy else { return }
        selectionGeneration = UUID(); let request = selectionGeneration
        guard learners.contains(where: { $0.id == id }) else { return }
        learnerID = id; trainings = []; assignments = []; productID = nil; termsAccepted = false
        if originalLesson == nil { trainingID = nil }
        isLoading = true
        do {
            let trainings: [SchoolTraining] = try await client.records(scope.schoolID, path: ["trainings"], query: [URLQueryItem(name: "learnerId", value: id.uuidString)])
            guard request == selectionGeneration, !invalidated, !Task.isCancelled else { return }
            self.trainings = trainings.filter { $0.status == "ACTIVE" || $0.id == originalLesson?.trainingId }
            isLoading = false
            if let trainingID { await selectTraining(trainingID) }
        } catch { guard request == selectionGeneration else { return }; isLoading = false; fail(error) }
    }
    func selectTraining(_ id: UUID) async {
        guard !invalidated, !isBusy else { return }
        guard trainings.contains(where: { $0.id == id }) else { return }
        selectionGeneration = UUID(); let request = selectionGeneration
        trainingID = id; assignments = []; productID = nil; termsAccepted = false; isLoading = true
        do {
            let records: [SchoolAssignment] = try await client.records(scope.schoolID, path: ["trainings", id.uuidString, "assignments"])
            guard request == selectionGeneration, !invalidated, !Task.isCancelled else { return }
            assignments = records; isLoading = false
            if originalLesson == nil { instructorID = roles.contains("ADMIN") ? nil : scope.membershipID }
        } catch { guard request == selectionGeneration else { return }; isLoading = false; fail(error) }
    }
    func loadAvailability() async {
        guard let instructorID, !invalidated else { return }
        let request = generation; availabilityGeneration = UUID(); let availabilityRequest = availabilityGeneration
        availability = []; closures = []
        do {
            let query = [URLQueryItem(name: "instructorMembershipId", value: instructorID.uuidString)]
            let rules: [SchoolAvailabilityRule] = try await client.records(scope.schoolID, path: ["availability-rules"], query: query)
            let closures: [SchoolClosure] = try await client.records(scope.schoolID, path: ["closures"], query: query)
            guard request == generation, availabilityRequest == availabilityGeneration, self.instructorID == instructorID, !Task.isCancelled else { return }
            availability = rules; self.closures = closures
        } catch { guard request == generation, availabilityRequest == availabilityGeneration else { return }; fail(error) }
    }
    func saveBooking() async -> Bool {
        guard validBooking, let instructorID, let trainingID else { return false }
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
        guard let lesson = originalLesson, lesson.status == "PLANNED", reason.count <= 1000,
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
            successMessage = "Enregistrement confirmé par l’école."; await load()
        } catch { guard request == generation else { return }; isBusy = false; fail(error) }
    }
    private func transmit(firstAttempt: Bool) async -> Bool {
        guard canRetry, let command = pending else { return false }
        let request = generation; isBusy = true; errorMessage = nil; successMessage = nil
        do {
            try outbox.save(command); try await client.send(command); try outbox.remove(command)
            guard request == generation else { return true }
            pending = nil; isBusy = false; successMessage = "Enregistrement confirmé par l’école."
            await load(); return true
        } catch {
            guard request == generation else { return false }
            if let failure = error as? SchoolPlanningFailure, failure.definitiveRejection {
                if firstAttempt {
                    do { try outbox.remove(command); pending = nil; needsReload = true }
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
