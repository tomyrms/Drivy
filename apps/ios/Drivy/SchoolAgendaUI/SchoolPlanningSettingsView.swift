import SwiftUI
import Observation
import Foundation

@MainActor @Observable final class SchoolPlanningSettingsWorkspace {
    let scope: SchoolCommandScope
    let client: SchoolPlanningClient
    private(set) var saved: SchoolPlanningDefaults?
    private(set) var offerings: [SchoolOffering] = []
    private(set) var products: [SchoolServiceProduct] = []
    private(set) var isLoading = false
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    private(set) var successMessage: String?
    private(set) var pending: PendingSchoolCommand?
    private(set) var storageAvailable = false
    var trainingCategoryCode = ""
    var serviceProductKey = ""
    @ObservationIgnored private let outbox: any SchoolCommandOutbox

    init(scope: SchoolCommandScope, client: SchoolPlanningClient, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        self.scope = scope; self.client = client; self.outbox = outbox
    }
    var categories: [String] { Array(Set(offerings.filter(\.enabled).map(\.categoryCode))).sorted() }
    var availableProducts: [SchoolServiceProduct] {
        products.filter { trainingCategoryCode.isEmpty || $0.categoryCode == trainingCategoryCode }
    }
    var canSave: Bool {
        saved != nil && storageAvailable && !isBusy && !isLoading && pending == nil
            && (trainingCategoryCode.isEmpty || categories.contains(trainingCategoryCode))
            && (serviceProductKey.isEmpty || availableProducts.contains { $0.productKey == serviceProductKey })
            && (trainingCategoryCode != (saved?.trainingCategoryCode ?? "") || serviceProductKey != (saved?.serviceProductKey ?? ""))
    }
    var canRetry: Bool { pending?.kind == .savePlanningDefaults && pending?.scope == scope && !isBusy && !isLoading }

    func load() async {
        guard !isBusy else { return }
        isLoading = true; errorMessage = nil; storageAvailable = false
        defer { isLoading = false }
        do {
            pending = try outbox.pending(for: scope); storageAvailable = true
            let person = try await client.reader.me()
            guard person.personId == scope.personID, person.memberships.contains(where: {
                $0.membershipId == scope.membershipID && $0.schoolId == scope.schoolID && $0.accessEpoch == scope.accessEpoch
                    && $0.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) })
            }) else { throw SchoolPlanningFailure.forbidden }
            let school = try await client.reader.school(id: scope.schoolID)
            let current = try await client.defaults(schoolID: scope.schoolID, membershipID: scope.membershipID)
            let offerings: [SchoolOffering] = try await client.records(scope.schoolID, path: ["offerings"])
            let policies: [SchoolCatalogPolicy] = try await client.records(scope.schoolID, path: ["policy-versions"])
            let products: [SchoolServiceProduct] = try await client.records(scope.schoolID, path: ["service-products"], query: [URLQueryItem(name: "current", value: "true")])
            let terms: [SchoolCommercialTerms] = try await client.records(scope.schoolID, path: ["commercial-terms"])
            try Task.checkCancellation()
            let date = SchoolCatalogFormatting.civilDate(Date(), timeZone: school.timeZone)
            self.offerings = offerings.filter { offering in offering.enabled && policies.contains { $0.id == offering.policyVersionId && $0.approved } }
            self.products = products.filter { product in
                product.enabled && product.current != false && product.type == "INDIVIDUAL_LESSON" && product.siteId == nil
                    && (product.durationMinutes ?? 0) > 0 && product.validFrom <= date && (product.validUntil.map { $0 >= date } ?? true)
                    && terms.contains { $0.id == product.termsVersionId && $0.approved && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) }
            }
            saved = current; trainingCategoryCode = current.trainingCategoryCode ?? ""; serviceProductKey = current.serviceProductKey ?? ""
        } catch {
            saved = nil
            if !(error is CancellationError) { errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
        }
    }
    func save() async {
        guard canSave, let saved else { return }
        let operation = UUID()
        do {
            let body = try JSONSerialization.data(withJSONObject: [
                "operationId": operation.uuidString,
                "trainingCategoryCode": trainingCategoryCode.isEmpty ? NSNull() : trainingCategoryCode as Any,
                "serviceProductKey": serviceProductKey.isEmpty ? NSNull() : serviceProductKey as Any
            ], options: [.sortedKeys])
            let command = PendingSchoolCommand(id: operation, scope: scope, kind: .savePlanningDefaults, resourceVersion: saved.version,
                createdAt: Date(), body: body, resourceID: scope.membershipID)
            try outbox.save(command); pending = command
            await send(command, fresh: true)
        } catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription }
    }
    func retry() async {
        guard canRetry, let pending else { return }
        await send(pending, fresh: false)
    }
    func verify() async {
        guard !isBusy, !isLoading, let command = pending, command.kind == .savePlanningDefaults else { return }
        isBusy = true; errorMessage = nil
        do {
            _ = try await client.receipt(for: command)
            try outbox.remove(command); pending = nil; successMessage = "Préférences enregistrées."
            isBusy = false; await load()
        } catch { isBusy = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
    }
    private func send(_ command: PendingSchoolCommand, fresh: Bool) async {
        isBusy = true; errorMessage = nil; successMessage = nil
        do {
            try outbox.save(command)
            try await client.send(command)
            try outbox.remove(command); pending = nil; successMessage = "Préférences enregistrées."
            isBusy = false; await load()
        } catch {
            if fresh, let failure = error as? SchoolPlanningFailure, failure.definitiveRejection {
                do { try outbox.remove(command); pending = nil }
                catch { storageAvailable = false }
            }
            isBusy = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription
        }
    }
}

struct SchoolPlanningSettingsView: View {
    @State private var model: SchoolPlanningSettingsWorkspace
    init(scope: SchoolCommandScope, client: SchoolPlanningClient) {
        _model = State(initialValue: SchoolPlanningSettingsWorkspace(scope: scope, client: client))
    }
    var body: some View {
        Form {
            if model.isLoading { Section { DrivyLoadingState(title: "Chargement des préférences…") }.drivyFormRows() }
            if let error = model.errorMessage {
                Section { SchoolErrorNotice(message: error, retry: { Task { await model.load() } }) }.drivyFormRows()
            }
            if let success = model.successMessage { Section { DrivyFormMessage(text: success, tone: .success) }.drivyFormRows() }
            if let pending = model.pending {
                Section {
                    DrivyPendingRequest(message: "Une demande attend sa confirmation.", reference: pending.id,
                        verify: pending.kind == .savePlanningDefaults ? { Task { await model.verify() } } : nil,
                        canVerify: !model.isBusy && !model.isLoading,
                        retry: model.canRetry ? { Task { await model.retry() } } : nil)
                }.drivyFormRows()
            }
            if model.saved != nil {
                Section {
                    Picker("Formation par défaut", selection: $model.trainingCategoryCode) {
                        Text("Aucune").tag("")
                        ForEach(model.categories, id: \.self) { Text("Permis \($0)").tag($0) }
                        if !model.trainingCategoryCode.isEmpty && !model.categories.contains(model.trainingCategoryCode) {
                            Text("Formation indisponible").tag(model.trainingCategoryCode)
                        }
                    }
                    .onChange(of: model.trainingCategoryCode) { _, _ in
                        if !model.availableProducts.contains(where: { $0.productKey == model.serviceProductKey }) { model.serviceProductKey = "" }
                    }
                    Picker("Tarif par défaut", selection: $model.serviceProductKey) {
                        Text("Aucun").tag("")
                        ForEach(model.availableProducts) { product in
                            Text("\(product.label) · \(SchoolCatalogFormatting.price(product.unitPriceCents))").tag(product.productKey)
                        }
                        if !model.serviceProductKey.isEmpty && !model.availableProducts.contains(where: { $0.productKey == model.serviceProductKey }) {
                            Text("Tarif indisponible").tag(model.serviceProductKey)
                        }
                    }
                }.drivyFormRows().disabled(model.isLoading || model.isBusy || model.pending != nil)
            }
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: SchoolFormLayout.maxWidth).frame(maxWidth: .infinity).background(DrivyTheme.canvas)
        .navigationTitle("Préférences de leçon").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            DrivyStickyActionBar {
                Button { Task { await model.save() } } label: {
                    DrivyBusyLabel(title: "Enregistrer", busyTitle: "Enregistrement…", isBusy: model.isBusy)
                }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canSave)
            }
        }
        .task { await model.load() }
    }
}
