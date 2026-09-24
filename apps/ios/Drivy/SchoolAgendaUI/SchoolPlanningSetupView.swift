import SwiftUI

struct SchoolPlanningSetupView: View {
    @Bindable var model: SchoolPlanningWorkspace
    var loadsOnAppear = true
    @Environment(\.dismiss) private var dismiss
    @State private var editor: PlanningSetupEditorRequest?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Le cadre des rendez-vous").font(.title2.weight(.bold))
                    Text("\(model.school?.name ?? "École") · \(model.timeZone)")
                        .font(.subheadline).foregroundStyle(DrivyTheme.muted)
                }.listRowBackground(Color.clear)
                SchoolPlanningFeedback(model: model)
                if !model.isLoading && model.school != nil {
                    if model.canConfigureCatalog { commercialSection }
                    availabilitySection
                    closureSection
                }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .navigationTitle("Réglages du planning").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .task {
                if loadsOnAppear { await model.load() }
                if model.instructorID == nil && !model.roles.contains("ADMIN") { model.instructorID = model.scope.membershipID }
                await model.loadAvailability()
            }
            .sheet(item: $editor) { request in SchoolPlanningSetupEditor(model: model, request: request) }
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
    private var commercialSection: some View {
        Section {
            ForEach(model.terms.sorted { $0.version > $1.version }) { terms in
                DisclosureGroup {
                    Text(terms.termsText).font(.subheadline).textSelection(.enabled)
                    Text(SchoolPlanningFormat.validity(terms.validFrom, until: terms.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    Button("Préparer une nouvelle version") { editor = .init(kind: .terms, terms: terms) }
                        .disabled(!model.canMutate)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(terms.label).font(.headline)
                        Text("Version \(terms.version) · \(terms.approved ? "Approuvées" : "Brouillon")")
                            .font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            Button { editor = .init(kind: .terms) } label: { Label("Créer des conditions", systemImage: "doc.text.badge.plus") }.disabled(!model.canMutate)
            ForEach(model.products.sorted { ($0.label, $0.version) < ($1.label, $1.version) }) { product in
                DisclosureGroup {
                    LabeledContent("Référence", value: product.productKey)
                    LabeledContent("Catégorie", value: product.categoryCode ?? "—")
                    LabeledContent("Prix unitaire", value: SchoolCatalogFormatting.price(product.unitPriceCents))
                    if let duration = product.durationMinutes { LabeledContent("Durée", value: "\(duration) min") }
                    Text(SchoolPlanningFormat.validity(product.validFrom, until: product.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                    Button("Préparer une nouvelle version") { editor = .init(kind: .product, product: product) }.disabled(!model.canMutate)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(product.label).font(.headline)
                        Text("\(SchoolCatalogFormatting.price(product.unitPriceCents)) · \(product.enabled ? "Active" : "Inactive") · v\(product.version)")
                            .font(.caption).foregroundStyle(DrivyTheme.muted)
                    }
                }
            }
            Button { editor = .init(kind: .product) } label: { Label("Créer une prestation", systemImage: "plus.circle") }
                .disabled(!model.canMutate || model.terms.isEmpty)
            if model.terms.isEmpty { Text("Créez les conditions avant la première prestation.").font(.caption).foregroundStyle(DrivyTheme.muted) }
        } header: { Text("Prestations et conditions") }
        footer: { Text("Une nouvelle version conserve les conditions des rendez-vous déjà pris.") }
    }
    private var availabilitySection: some View {
        Section {
            Picker("Moniteur", selection: $model.instructorID) {
                Text("Choisir un moniteur").tag(nil as UUID?)
                ForEach(model.instructors) { value in Text(value.displayName).tag(Optional(value.id)) }
            }.onChange(of: model.instructorID) { _, _ in Task { await model.loadAvailability() } }
            if model.instructorID != nil {
                ForEach(model.availability) { rule in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.headline)
                        Text("\(rule.localStart) – \(rule.localEnd)")
                        Text(SchoolPlanningFormat.validity(rule.validFrom, until: rule.validUntil)).font(.caption).foregroundStyle(DrivyTheme.muted)
                        HStack(spacing: 24) {
                            Button("Modifier") { editor = .init(kind: .availability, rule: rule) }
                            Button("Retirer", role: .destructive) { editor = .init(kind: .removeAvailability, rule: rule) }
                        }.buttonStyle(.borderless).disabled(!model.canMutate)
                    }.padding(.vertical, 5)
                }
                if model.availability.isEmpty { Text("Aucune plage d’ouverture pour ce moniteur.").foregroundStyle(DrivyTheme.muted) }
                Button { editor = .init(kind: .availability) } label: { Label("Ajouter une disponibilité", systemImage: "calendar.badge.plus") }.disabled(!model.canMutate)
            }
        } header: { Text("Disponibilités") }
        footer: { Text("Les jours et horaires sont exprimés dans le fuseau de l’école. Les rendez-vous existants sont protégés.") }
    }
    private var closureSection: some View {
        Section {
            if model.instructorID != nil {
                ForEach(model.closures) { closure in
                    VStack(alignment: .leading, spacing: 9) {
                        Text(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone)).font(.headline)
                        if let reason = closure.reason, !reason.isEmpty { Text(reason).font(.subheadline).foregroundStyle(DrivyTheme.muted) }
                        Button("Retirer cette fermeture", role: .destructive) { editor = .init(kind: .removeClosure, closure: closure) }
                            .disabled(!model.canMutate)
                    }.padding(.vertical, 5)
                }
                if model.closures.isEmpty { Text("Aucune fermeture enregistrée.").foregroundStyle(DrivyTheme.muted) }
                Button { editor = .init(kind: .closure) } label: { Label("Ajouter une fermeture", systemImage: "calendar.badge.minus") }.disabled(!model.canMutate)
            } else { Text("Choisissez un moniteur pour consulter les fermetures.").foregroundStyle(DrivyTheme.muted) }
        } header: { Text("Fermetures et absences") }
    }
}

private enum PlanningSetupEditorKind { case terms, product, availability, closure, removeAvailability, removeClosure }
private struct PlanningSetupEditorRequest: Identifiable {
    let id = UUID()
    let kind: PlanningSetupEditorKind
    var terms: SchoolCommercialTerms? = nil
    var product: SchoolServiceProduct? = nil
    var rule: SchoolAvailabilityRule? = nil
    var closure: SchoolClosure? = nil
}

private struct SchoolPlanningSetupEditor: View {
    @Bindable var model: SchoolPlanningWorkspace
    let request: PlanningSetupEditorRequest
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var reference = ""
    @State private var category = ""
    @State private var termsText = ""
    @State private var reason = ""
    @State private var price = ""
    @State private var duration = ""
    @State private var unit = ""
    @State private var termsID: UUID?
    @State private var validFrom = Date()
    @State private var validUntil = Date()
    @State private var starts = Date()
    @State private var ends = Date().addingTimeInterval(3600)
    @State private var hasEnd = false
    @State private var approved = false
    @State private var enabled = false
    @State private var confirmed = false
    @State private var days = Set<Int>()
    @State private var localStart = ""
    @State private var localEnd = ""

    private var title: String {
        switch request.kind {
        case .terms: "Conditions commerciales"
        case .product: "Prestation de conduite"
        case .availability: request.rule == nil ? "Ajouter une disponibilité" : "Modifier la disponibilité"
        case .closure: "Ajouter une fermeture"
        case .removeAvailability: "Retirer la disponibilité"
        case .removeClosure: "Retirer la fermeture"
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                SchoolPlanningFeedback(model: model)
                fields
                Section {
                    Toggle(confirmationText, isOn: $confirmed)
                    Button(action: save) {
                        Text(actionTitle).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(DrivyPrimaryButtonStyle()).disabled(!valid || !confirmed || !model.canMutate)
                } footer: { Text("La modification est appliquée uniquement après confirmation par l’école.") }
            }
            .scrollContentBackground(.hidden).background(DrivyTheme.canvas)
            .environment(\.timeZone, TimeZone(identifier: model.timeZone) ?? .current)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() }.disabled(model.isBusy) } }
            .onAppear(perform: populate)
        }
        .interactiveDismissDisabled(model.isBusy)
        .tint(DrivyTheme.accent)
    }
    @ViewBuilder private var fields: some View {
        switch request.kind {
        case .terms: termsFields
        case .product: productFields
        case .availability: availabilityFields
        case .closure:
            Section {
                instructorLabel
                DatePicker("Début", selection: $starts)
                DatePicker("Fin", selection: $ends, in: starts...)
                TextField("Motif facultatif", text: $reason, axis: .vertical).lineLimit(2...5)
            } footer: { Text("Les leçons concernées doivent être déplacées ou annulées avant d’ajouter une fermeture.") }
        case .removeAvailability, .removeClosure:
            Section {
                if let rule = request.rule {
                    Text(SchoolPlanningFormat.weekdays(rule.weekdays)).font(.headline)
                    Text("\(rule.localStart) – \(rule.localEnd)")
                }
                if let closure = request.closure { Text(SchoolPlanningFormat.interval(closure.startsAt, closure.endsAt, zone: model.timeZone)).font(.headline) }
                TextField("Motif du retrait", text: $reason, axis: .vertical).lineLimit(3...6)
            }
        }
    }
    private var termsFields: some View {
        Group {
            Section("Les textes") {
                TextField("Nom des conditions", text: $label)
                TextField("Conditions commerciales de l’école", text: $termsText, axis: .vertical).lineLimit(8...20)
            }
            validityFields
            Section {
                Toggle("Approuver les textes affichés", isOn: $approved)
                TextField("Motif de cette version", text: $reason, axis: .vertical).lineLimit(2...5)
            } footer: { Text("L’approbation porte sur le texte affiché. Aucune approbation n’est préremplie.") }
        }
    }
    private var productFields: some View {
        Group {
            Section("La prestation") {
                TextField("Nom de la prestation", text: $label)
                TextField("Référence", text: $reference).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Catégorie de permis", text: $category).textInputAutocapitalization(.characters)
                TextField("Durée en minutes", text: $duration).keyboardType(.numberPad)
                TextField("Unité facturée", text: $unit)
                TextField("Prix unitaire en CHF", text: $price).keyboardType(.decimalPad)
            }
            validityFields
            Section {
                Picker("Conditions commerciales", selection: $termsID) {
                    Text("Choisir les conditions").tag(nil as UUID?)
                    ForEach(model.terms) { terms in Text("\(terms.label) · v\(terms.version)").tag(Optional(terms.id)) }
                }
                if let selected = model.terms.first(where: { $0.id == termsID }) {
                    DisclosureGroup("Relire les conditions") { Text(selected.termsText).font(.subheadline).textSelection(.enabled) }
                    if !selected.approved { Text("Ces conditions ne sont pas approuvées. La prestation doit rester inactive.").font(.caption).foregroundStyle(DrivyTheme.warning) }
                }
                Toggle("Activer cette prestation", isOn: $enabled)
            } footer: { Text("Cette version concerne une leçon individuelle. Le tarif doit être explicitement convenu à chaque réservation.") }
        }
    }
    private var availabilityFields: some View {
        Group {
            Section {
                instructorLabel
                ForEach(1...7, id: \.self) { day in
                    Toggle(SchoolPlanningFormat.weekdays([day]), isOn: Binding(get: { days.contains(day) }, set: { selected in
                        if selected { days.insert(day) } else { days.remove(day) }
                    }))
                }
            } header: { Text("Les jours") }
            Section {
                TextField("Début, ex. 08:00", text: $localStart).keyboardType(.numbersAndPunctuation)
                TextField("Fin, ex. 18:00", text: $localEnd).keyboardType(.numbersAndPunctuation)
            } header: { Text("Heures locales · \(model.timeZone)") }
            validityFields
        }
    }
    private var instructorLabel: some View {
        LabeledContent("Moniteur", value: model.instructors.first(where: { $0.id == (request.rule?.instructorMembershipId ?? model.instructorID) })?.displayName ?? "Moniteur choisi")
    }
    private var validityFields: some View {
        Section("Validité") {
            DatePicker("Dès le", selection: $validFrom, displayedComponents: .date)
            Toggle("Définir une date de fin", isOn: $hasEnd)
            if hasEnd { DatePicker("Jusqu’au", selection: $validUntil, in: validFrom..., displayedComponents: .date) }
        }
    }
    private var confirmationText: String {
        switch request.kind {
        case .terms: "J’ai relu les textes et leur validité"
        case .product: "J’ai vérifié le tarif et les conditions"
        case .availability: "Ces horaires sont corrects"
        case .closure: "Je confirme cette période de fermeture"
        case .removeAvailability, .removeClosure: "Je confirme le retrait"
        }
    }
    private var actionTitle: String {
        switch request.kind {
        case .terms: approved ? "Créer les conditions approuvées" : "Enregistrer le brouillon"
        case .product: enabled ? "Créer la prestation active" : "Créer la prestation inactive"
        case .availability: request.rule == nil ? "Ajouter la disponibilité" : "Enregistrer les horaires"
        case .closure: "Fermer cette période"
        case .removeAvailability, .removeClosure: "Confirmer le retrait"
        }
    }
    private var valid: Bool {
        guard !hasEnd || validUntil >= validFrom else { return false }
        switch request.kind {
        case .terms: return nonBlank(label, max: 200) && nonBlank(termsText, max: 20_000) && nonBlank(reason, max: 1000)
        case .product:
            guard nonBlank(label, max: 200), nonBlank(reference, max: 100), nonBlank(category, max: 30),
                  nonBlank(unit, max: 100), let duration = Int(duration), (1...480).contains(duration),
                  SchoolCatalogFormatting.cents(price) != nil, let terms = model.terms.first(where: { $0.id == termsID }) else { return false }
            return !enabled || terms.approved
        case .availability: return !days.isEmpty && validTime(localStart) && validTime(localEnd) && localEnd > localStart && (request.rule?.instructorMembershipId ?? model.instructorID) != nil
        case .closure: return ends > starts && reason.count <= 1000 && model.instructorID != nil
        case .removeAvailability, .removeClosure: return nonBlank(reason, max: 1000)
        }
    }
    private func nonBlank(_ text: String, max: Int) -> Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= max }
    private func validTime(_ text: String) -> Bool {
        text.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
    }
    private func populate() {
        if let terms = request.terms { label = terms.label; termsText = terms.termsText }
        if let product = request.product {
            label = product.label; reference = product.productKey; category = product.categoryCode ?? ""
            duration = product.durationMinutes.map(String.init) ?? ""; unit = product.unitLabel
            price = NSDecimalNumber(decimal: Decimal(product.unitPriceCents) / 100).stringValue; termsID = product.termsVersionId
        }
        if let rule = request.rule {
            days = Set(rule.weekdays); localStart = rule.localStart; localEnd = rule.localEnd
            let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian); format.locale = Locale(identifier: "en_US_POSIX")
            format.timeZone = TimeZone(identifier: model.timeZone); format.dateFormat = "yyyy-MM-dd"
            validFrom = format.date(from: rule.validFrom) ?? validFrom
            if let end = rule.validUntil.flatMap({ format.date(from: $0) }) { validUntil = end; hasEnd = true }
        }
    }
    private func save() {
        guard valid && confirmed else { return }
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var body: [String: Any] = [:]
        let kind: SchoolCommandKind
        var resourceID: UUID?, version = 0
        let date = SchoolCatalogFormatting.civilDate(validFrom, timeZone: model.timeZone)
        let until: Any = hasEnd ? SchoolCatalogFormatting.civilDate(validUntil, timeZone: model.timeZone) as Any : NSNull()
        switch request.kind {
        case .terms:
            kind = .createCommercialTerms
            body = ["label": trim(label), "termsText": trim(termsText), "validFrom": date, "validUntil": until,
                    "approved": approved, "approvalReason": trim(reason)]
        case .product:
            guard let termsID, let duration = Int(duration), let cents = SchoolCatalogFormatting.cents(price) else { return }
            kind = .createServiceProduct
            body = ["productKey": trim(reference), "label": trim(label), "type": "INDIVIDUAL_LESSON", "categoryCode": trim(category),
                    "siteId": NSNull(), "durationMinutes": duration, "unitLabel": trim(unit), "unitPriceCents": cents,
                    "validFrom": date, "validUntil": until, "termsVersionId": termsID.uuidString, "enabled": enabled]
        case .availability:
            guard let instructor = request.rule?.instructorMembershipId ?? model.instructorID else { return }
            kind = request.rule == nil ? .createAvailabilityRule : .updateAvailabilityRule
            resourceID = request.rule?.id; version = request.rule?.version ?? 0
            body = ["instructorMembershipId": instructor.uuidString, "weekdays": days.sorted(), "localStart": localStart,
                    "localEnd": localEnd, "validFrom": date, "validUntil": until]
        case .closure:
            guard let instructor = model.instructorID else { return }
            kind = .createClosure; let iso = ISO8601DateFormatter()
            body = ["instructorMembershipId": instructor.uuidString, "startsAt": iso.string(from: starts), "endsAt": iso.string(from: ends), "reason": trim(reason)]
        case .removeAvailability:
            guard let rule = request.rule else { return }
            kind = .removeAvailabilityRule; resourceID = rule.id; version = rule.version; body = ["reason": trim(reason)]
        case .removeClosure:
            guard let closure = request.closure else { return }
            kind = .removeClosure; resourceID = closure.id; version = closure.version; body = ["reason": trim(reason)]
        }
        Task {
            if await model.submit(kind, body: body, resourceID: resourceID, version: version) {
                await model.loadAvailability(); dismiss()
            }
        }
    }
}
