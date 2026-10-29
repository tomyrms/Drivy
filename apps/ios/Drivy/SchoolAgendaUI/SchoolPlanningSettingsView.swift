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
    /// Demande que l’école a déclaré ne pas connaître : elle peut être renvoyée comme neuve, ou abandonnée.
    private(set) var absentPendingID: UUID?
    var pendingAbsent: Bool { pending != nil && pending?.id == absentPendingID }
    private(set) var storageAvailable = false
    private(set) var contextCurrent = false
    private(set) var conflictingDefaults: SchoolPlanningDefaults?
    private(set) var removedProductNotice: String?
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
    var hasChanges: Bool {
        trainingCategoryCode != (saved?.trainingCategoryCode ?? "") || serviceProductKey != (saved?.serviceProductKey ?? "")
    }
    var canSave: Bool {
        saved != nil && contextCurrent && storageAvailable && !isBusy && !isLoading && pending == nil
            && (trainingCategoryCode.isEmpty || categories.contains(trainingCategoryCode))
            && (serviceProductKey.isEmpty || availableProducts.contains { $0.productKey == serviceProductKey })
            && hasChanges
    }
    var canRetry: Bool { pending?.kind == .savePlanningDefaults && pending?.scope == scope && !isBusy && !isLoading }
    var draft: SchoolPlanningPreferenceDraft {
        SchoolPlanningPreferenceDraft(trainingCategoryCode: trainingCategoryCode, serviceProductKey: serviceProductKey)
    }

    func selectCategory(_ code: String) {
        guard code != trainingCategoryCode else { return }
        let previous = products.first { $0.productKey == serviceProductKey }?.label ?? "précédent"
        trainingCategoryCode = code
        if !serviceProductKey.isEmpty && !availableProducts.contains(where: { $0.productKey == serviceProductKey }) {
            serviceProductKey = ""
            removedProductNotice = "Le tarif \(previous) ne s’applique plus à cette formation. Choisis un tarif ou garde aucune préférence."
        }
        successMessage = nil
    }

    func selectProduct(_ key: String) {
        serviceProductKey = key; removedProductNotice = nil; successMessage = nil
    }

    func load(keepingEdits: Bool = true) async {
        guard !isBusy, !isLoading else { return }
        let draftAtStart = draft
        let hadEdits = keepingEdits && saved != nil && hasChanges
        isLoading = true; errorMessage = nil; storageAvailable = false; contextCurrent = false; conflictingDefaults = nil
        defer { isLoading = false }
        do {
            pending = try outbox.pending(for: scope, domain: .planningPreferences); storageAvailable = true
            let person = try await client.reader.me()
            guard person.personId == scope.personID, person.memberships.contains(where: {
                $0.membershipId == scope.membershipID && $0.schoolId == scope.schoolID && $0.accessEpoch == scope.accessEpoch
                    && $0.roles.contains(where: { ["ADMIN", "INSTRUCTOR"].contains($0) })
            }) else { throw SchoolPlanningFailure.forbidden }
            // Droits relus d’abord ; les lectures suivantes sont indépendantes et partent ensemble.
            let schoolRead = Task<SchoolDetails, any Error> { @MainActor in try await self.client.reader.school(id: self.scope.schoolID) }
            let defaultsRead = Task<SchoolPlanningDefaults, any Error> { @MainActor in
                try await self.client.defaults(schoolID: self.scope.schoolID, membershipID: self.scope.membershipID)
            }
            let offeringsRead = Task<[SchoolOffering], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["offerings"]) }
            let policiesRead = Task<[SchoolCatalogPolicy], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["policy-versions"]) }
            let productsRead = Task<[SchoolServiceProduct], any Error> { @MainActor in
                try await self.client.records(self.scope.schoolID, path: ["service-products"], query: [URLQueryItem(name: "current", value: "true")])
            }
            let termsRead = Task<[SchoolCommercialTerms], any Error> { @MainActor in try await self.client.records(self.scope.schoolID, path: ["commercial-terms"]) }
            defer {
                schoolRead.cancel(); defaultsRead.cancel(); offeringsRead.cancel(); policiesRead.cancel()
                productsRead.cancel(); termsRead.cancel()
            }
            let school = try await schoolRead.readValue
            let current = try await defaultsRead.readValue
            let offerings = try await offeringsRead.readValue
            let policies = try await policiesRead.readValue
            let products = try await productsRead.readValue
            let terms = try await termsRead.readValue
            try Task.checkCancellation()
            let date = SchoolCatalogFormatting.civilDate(Date(), timeZone: school.timeZone)
            // Une réponse tardive ne remplace jamais une saisie modifiée après le début de la lecture.
            let preservingEdits = hadEdits || draft != draftAtStart
            self.offerings = offerings.filter { offering in offering.enabled && policies.contains { $0.id == offering.policyVersionId && $0.approved } }
            self.products = products.filter { product in
                product.enabled && product.current != false && product.type == "INDIVIDUAL_LESSON" && product.siteId == nil
                    && (product.durationMinutes ?? 0) > 0 && product.validFrom <= date && (product.validUntil.map { $0 >= date } ?? true)
                    && terms.contains { $0.id == product.termsVersionId && $0.approved && $0.validFrom <= date && ($0.validUntil.map { $0 >= date } ?? true) }
            }
            if preservingEdits, saved?.version != current.version {
                conflictingDefaults = current
                errorMessage = "Les préférences ont changé à l’école. Compare les deux versions avant de continuer."
            } else {
                saved = current; contextCurrent = true; conflictingDefaults = nil
            }
            if !preservingEdits {
                trainingCategoryCode = current.trainingCategoryCode ?? ""; serviceProductKey = current.serviceProductKey ?? ""
                removedProductNotice = nil
            }
        } catch {
            if error as? SchoolPlanningFailure == .forbidden || error as? SchoolPlanningFailure == .unauthorized
                || error as? SchoolAPIError == .forbidden || error as? SchoolAPIError == .unauthorized {
                saved = nil; conflictingDefaults = nil; offerings = []; products = []; trainingCategoryCode = ""; serviceProductKey = ""
                removedProductNotice = nil
            }
            if !(error is CancellationError) { errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
        }
    }
    func conflictReview() -> SchoolPlanningPreferenceConflict? {
        guard let current = conflictingDefaults else { return nil }
        return SchoolPlanningPreferenceConflict(local: draft, remote: current)
    }
    func canResolve(_ review: SchoolPlanningPreferenceConflict) -> Bool {
        !isBusy && !isLoading && pending == nil && conflictingDefaults?.version == review.remote.version && draft == review.local
    }
    @discardableResult func resolve(_ review: SchoolPlanningPreferenceConflict, keepLocal: Bool) -> Bool {
        guard canResolve(review), let current = conflictingDefaults else { return false }
        saved = current
        if !keepLocal {
            trainingCategoryCode = current.trainingCategoryCode ?? ""
            serviceProductKey = current.serviceProductKey ?? ""
            removedProductNotice = nil
        }
        conflictingDefaults = nil; contextCurrent = true; errorMessage = nil; successMessage = nil
        if !trainingCategoryCode.isEmpty && !categories.contains(trainingCategoryCode) {
            errorMessage = "La formation choisie n’est plus disponible. Choisis une formation ou aucune préférence."
        } else if !serviceProductKey.isEmpty && !availableProducts.contains(where: { $0.productKey == serviceProductKey }) {
            errorMessage = "Le tarif choisi n’est plus disponible. Choisis un tarif ou aucune préférence."
        }
        return true
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
    /// Toute demande restée en file se vérifie ici, même partie d’un autre écran : sans cela rien ne la résout.
    func verify() async {
        guard !isBusy, !isLoading, let command = pending else { return }
        isBusy = true; errorMessage = nil
        do {
            _ = try await client.receipt(for: command)
            try outbox.remove(command); pending = nil; absentPendingID = nil
            successMessage = command.kind == .savePlanningDefaults ? "Préférences enregistrées." : nil
            isBusy = false; await load(keepingEdits: command.kind != .savePlanningDefaults)
        } catch SchoolPlanningFailure.notFound {
            isBusy = false; absentPendingID = command.id
        } catch { isBusy = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription }
    }
    /// Retire une demande que l’école ne connaît pas : rien n’a été enregistré.
    func abandon() async {
        guard !isBusy, !isLoading, let command = pending, pendingAbsent else { return }
        do { try outbox.remove(command) }
        catch { storageAvailable = false; errorMessage = SchoolConfigurationFailure.storage.localizedDescription; return }
        pending = nil; absentPendingID = nil; errorMessage = nil
        await load(keepingEdits: true)
    }
    private func send(_ command: PendingSchoolCommand, fresh: Bool) async {
        let draftAtSend = draft
        isBusy = true; errorMessage = nil; successMessage = nil
        do {
            try outbox.save(command)
            try await client.send(command)
            try outbox.remove(command); pending = nil; successMessage = "Préférences enregistrées."
            isBusy = false; await load(keepingEdits: draft != draftAtSend)
        } catch {
            // Refus motivé, ou service qui ne connaît pas cette écriture (404) : l’école a répondu, rien n’est
            // enregistré. La demande quitte la file au lieu de bloquer toutes les autres écritures de l’école.
            if fresh || command.id == absentPendingID, let failure = error as? SchoolPlanningFailure,
               failure.definitiveRejection || failure == .notFound {
                do { try outbox.remove(command); pending = nil; absentPendingID = nil }
                catch { storageAvailable = false }
                if failure == .notFound, pending == nil {
                    isBusy = false
                    errorMessage = "L’école n’a pas pu enregistrer ces préférences. Rien n’a été modifié."
                    return
                }
            }
            isBusy = false; errorMessage = (error as? LocalizedError)?.errorDescription ?? SchoolPlanningFailure.unavailable.localizedDescription
            if error as? SchoolPlanningFailure == .conflict, pending == nil { await load(keepingEdits: true) }
        }
    }
}

struct SchoolPlanningSettingsView: View {
    @State private var model: SchoolPlanningSettingsWorkspace
    @State private var confirmsDiscard = false
    @State private var conflictReview: SchoolPlanningPreferenceConflict?
    @Environment(\.dismiss) private var dismiss
    init(scope: SchoolCommandScope, client: SchoolPlanningClient, outbox: any SchoolCommandOutbox = EncryptedSchoolCommandOutbox()) {
        _model = State(initialValue: SchoolPlanningSettingsWorkspace(scope: scope, client: client, outbox: outbox))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DrivySpacing.m) {
                if model.saved == nil && (model.isLoading || model.errorMessage == nil) {
                    DrivySkeletonRows(count: 2).drivySkeleton("Chargement des préférences…")
                }
                if let error = model.errorMessage {
                    VStack(alignment: .leading, spacing: DrivySpacing.s) {
                        if model.conflictingDefaults != nil {
                            DrivyFormMessage(text: error, tone: .danger)
                            Button("Comparer les préférences") { conflictReview = model.conflictReview() }
                                .frame(minHeight: DrivyLayout.tapTarget)
                                .disabled(model.isBusy || model.isLoading || model.pending != nil)
                                .accessibilityIdentifier("planning-settings-compare")
                        } else {
                            SchoolErrorNotice(message: error, retry: { Task { await model.load() } })
                        }
                    }
                }
                if let success = model.successMessage, !model.hasChanges { DrivyFormMessage(text: success, tone: .success) }
                if let pending = model.pending {
                    DrivyPendingRequest(message: pending.waitingMessage(absent: model.pendingAbsent), reference: pending.id,
                        verify: model.pendingAbsent ? nil : { Task { await model.verify() } },
                        canVerify: !model.isBusy && !model.isLoading,
                        retry: model.canRetry ? { Task { await model.retry() } } : nil,
                        abandon: model.pendingAbsent ? { Task { await model.abandon() } } : nil,
                        canAbandon: !model.isBusy && !model.isLoading)
                }
                if model.saved != nil {
                    DrivyRowGroup {
                        preferenceField("Formation par défaut") {
                            Picker("Formation par défaut", selection: Binding(get: { model.trainingCategoryCode }, set: { model.selectCategory($0) })) {
                                Text("Aucune préférence").tag("")
                                ForEach(model.categories, id: \.self) { DrivingLicenseLabel(title: "Permis \($0)", code: $0).tag($0) }
                                if !model.trainingCategoryCode.isEmpty && !model.categories.contains(model.trainingCategoryCode) {
                                    Text("Formation indisponible").tag(model.trainingCategoryCode)
                                }
                            }
                        }
                        preferenceField("Tarif par défaut") {
                            Picker("Tarif par défaut", selection: Binding(get: { model.serviceProductKey }, set: { model.selectProduct($0) })) {
                                Text("Aucune préférence").tag("")
                                ForEach(model.availableProducts) { product in
                                    Text(SchoolPlanningPreferenceFormat.product(product)).tag(product.productKey)
                                }
                                if !model.serviceProductKey.isEmpty && !model.availableProducts.contains(where: { $0.productKey == model.serviceProductKey }) {
                                    Text("Tarif indisponible").tag(model.serviceProductKey)
                                }
                            }
                            if let notice = model.removedProductNotice {
                                Text(notice).font(.footnote).foregroundStyle(DrivyTheme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityIdentifier("planning-settings-product-removed")
                                Button("Garder aucune préférence") { model.selectProduct("") }
                                    .frame(minHeight: DrivyLayout.tapTarget)
                            }
                        }
                    }.disabled(model.isLoading || model.isBusy || model.pending != nil)
                }
                Button { Task { await model.save() } } label: {
                    DrivyBusyLabel(title: "Enregistrer les préférences", busyTitle: "Enregistrement des préférences…", isBusy: model.isBusy)
                }
                .buttonStyle(DrivyPrimaryButtonStyle()).disabled(!model.canSave)
                .accessibilityIdentifier("planning-settings-save")
            }
            .drivyPageContent(maxWidth: SchoolFormLayout.maxWidth)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(DrivyTheme.surface)
        .navigationTitle("Préférences de leçon").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Fermer") {
                    if model.hasChanges { confirmsDiscard = true } else { dismiss() }
                }.disabled(model.isBusy)
            }
        }
        .interactiveDismissDisabled(model.hasChanges || model.isBusy)
        .alert("Quitter sans enregistrer tes changements ?", isPresented: $confirmsDiscard) {
            Button("Quitter sans enregistrer", role: .destructive) { dismiss() }
            Button("Continuer la modification", role: .cancel) { }
        } message: {
            // Dit seulement quand une demande attend vraiment : sans elle, la question se suffit.
            if model.pending != nil {
                Text("Une demande déjà envoyée reste conservée sur cet appareil jusqu’à confirmation.")
            }
        }
        .task { await model.load() }
        .onChange(of: model.removedProductNotice) { _, notice in
            if let notice { AccessibilityNotification.Announcement(notice).post() }
        }
        .sheet(item: $conflictReview) { review in SchoolPlanningConflictView(model: model, review: review) }
    }

    private func preferenceField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(DrivyTheme.text)
                .fixedSize(horizontal: false, vertical: true)
            content().labelsHidden().pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: DrivyLayout.tapTarget, alignment: .leading)
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, DrivySpacing.xs)
    }
}

private struct SchoolPlanningConflictView: View {
    let model: SchoolPlanningSettingsWorkspace
    let review: SchoolPlanningPreferenceConflict
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tes choix non enregistrés") {
                    values(category: review.local.trainingCategoryCode, product: review.local.serviceProductKey)
                }
                Section("Version actuelle à l’école") {
                    values(category: review.remote.trainingCategoryCode ?? "", product: review.remote.serviceProductKey ?? "")
                }
                if !model.canResolve(review) {
                    Text("Ces choix ont changé. Ferme cette comparaison puis ouvre-la à nouveau.")
                        .foregroundStyle(DrivyTheme.danger)
                }
                Section {
                    Button("Utiliser la version de l’école") {
                        if model.resolve(review, keepLocal: false) { dismiss() }
                    }.accessibilityIdentifier("planning-settings-use-remote")
                    Button("Garder mes choix à enregistrer") {
                        if model.resolve(review, keepLocal: true) { dismiss() }
                    }.accessibilityIdentifier("planning-settings-keep-local")
                }.disabled(!model.canResolve(review))
            }
            .navigationTitle("Comparer les préférences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
    }

    @ViewBuilder private func values(category: String, product: String) -> some View {
        LabeledContent("Formation", value: SchoolPlanningPreferenceFormat.category(category))
        VStack(alignment: .leading, spacing: DrivySpacing.xxs) {
            Text("Tarif").foregroundStyle(DrivyTheme.muted)
            Text(SchoolPlanningPreferenceFormat.product(key: product, in: model.products))
                .fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
}
